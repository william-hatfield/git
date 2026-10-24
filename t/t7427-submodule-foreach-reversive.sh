#!/bin/sh
#
# Copyright (c) 2026 William Hatfield
#

test_description='git submodule foreach --reverse-traversal

Check that --reverse-traversal visits submodules in the reverse of their
usual order, and that, together with --recursive, each submodule is
visited after the submodules nested in it.
'

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

# Create a commit with some content in repository $1.
create_content () {
	echo "$2" >"$1/file" &&
	git -C "$1" add file &&
	test_tick &&
	git -C "$1" commit -m "$1 commit"
}

# Add submodules $2... to repository $1 and commit.
add_submodules () {
	parent=$1 &&
	shift &&
	for child in "$@"
	do
		git -C "$parent" submodule add ../"$child" "$child" ||
		return 1
	done &&
	test_tick &&
	git -C "$parent" commit -m "add $*"
}

test_expect_success 'setup' '
	git config --global protocol.file.allow always &&
	#
	# Resulting layout:
	#
	#   top
	#   +-- sub0
	#   +-- sub1
	#   |   `-- sub2
	#   +-- sub3
	#   |   +-- sub4
	#   |   `-- sub5
	#   `-- sub6
	#       `-- sub7
	#           +-- sub8
	#           `-- sub9
	#
	mkdir reversive &&
	(
		cd reversive &&
		for r in top sub0 sub1 sub2 sub3 sub4 sub5 sub6 sub7 sub8 sub9
		do
			test_create_repo $r &&
			create_content $r $r || return 1
		done &&
		add_submodules sub1 sub2 &&
		add_submodules sub3 sub4 sub5 &&
		add_submodules sub7 sub8 sub9 &&
		add_submodules sub6 sub7 &&
		add_submodules top sub0 sub1 sub3 sub6 &&
		git -C top submodule update --init --recursive
	)
'

test_expect_success 'default order is unchanged' '
	git -C reversive/top submodule --quiet foreach --recursive \
		"echo \$displaypath" >actual &&
	cat >expect <<-\EOF &&
	sub0
	sub1
	sub1/sub2
	sub3
	sub3/sub4
	sub3/sub5
	sub6
	sub6/sub7
	sub6/sub7/sub8
	sub6/sub7/sub9
	EOF
	test_cmp expect actual
'

test_expect_success '--recursive --reverse-traversal visits each submodule before its superproject' '
	git -C reversive/top submodule --quiet foreach --recursive \
		--reverse-traversal "echo \$displaypath" >actual &&
	cat >expect <<-\EOF &&
	sub6/sub7/sub9
	sub6/sub7/sub8
	sub6/sub7
	sub6
	sub3/sub5
	sub3/sub4
	sub3
	sub1/sub2
	sub1
	sub0
	EOF
	test_cmp expect actual
'

test_expect_success '--reverse-traversal without --recursive only reverses the top level' '
	git -C reversive/top submodule --quiet foreach \
		--reverse-traversal "echo \$displaypath" >actual &&
	cat >expect <<-\EOF &&
	sub6
	sub3
	sub1
	sub0
	EOF
	test_cmp expect actual
'

test_expect_success '--reverse-traversal announces each submodule after the submodules nested in it' '
	git -C reversive/top submodule foreach --recursive \
		--reverse-traversal true >out &&
	sed -n -e "s/^Entering .\(.*\).\$/\1/p" out >actual &&
	cat >expect <<-\EOF &&
	sub6/sub7/sub9
	sub6/sub7/sub8
	sub6/sub7
	sub6
	sub3/sub5
	sub3/sub4
	sub3
	sub1/sub2
	sub1
	sub0
	EOF
	test_cmp expect actual &&
	git -C reversive/top submodule foreach --quiet --recursive \
		--reverse-traversal true >out 2>&1 &&
	test_must_be_empty out
'

test_expect_success 'a failure stops the traversal' '
	test_must_fail git -C reversive/top submodule --quiet foreach \
		--recursive --reverse-traversal \
		"echo \$displaypath; test \$name != sub8" >actual 2>err &&
	cat >expect <<-\EOF &&
	sub6/sub7/sub9
	sub6/sub7/sub8
	EOF
	test_cmp expect actual
'

test_expect_success 'submodules that are not checked out are skipped' '
	git clone reversive/top partial &&
	git -C partial submodule update --init sub3 sub6 &&
	git -C partial/sub6 submodule update --init sub7 &&
	git -C partial submodule --quiet foreach --recursive \
		--reverse-traversal "echo \$displaypath" >actual &&
	cat >expect <<-\EOF &&
	sub6/sub7
	sub6
	sub3
	EOF
	test_cmp expect actual
'

test_expect_success 'submodules checked out by the command are not visited' '
	git clone reversive/top dynamic &&
	git -C dynamic submodule update --init sub1 &&
	git -C dynamic submodule --quiet foreach --recursive \
		--reverse-traversal \
		"echo \$displaypath; git submodule update --init --quiet" \
		>actual &&
	echo sub1 >expect &&
	test_cmp expect actual &&
	git -C dynamic/sub1/sub2 rev-parse --show-toplevel >actual &&
	(cd dynamic/sub1/sub2 && pwd -P) >expect &&
	test_cmp expect actual &&

	git clone reversive/top dynamic-usual &&
	git -C dynamic-usual submodule update --init sub1 &&
	git -C dynamic-usual submodule --quiet foreach --recursive \
		"echo \$displaypath; git submodule update --init --quiet" \
		>actual &&
	cat >expect <<-\EOF &&
	sub1
	sub1/sub2
	EOF
	test_cmp expect actual
'

test_expect_success 'committing in reverse order leaves nested submodules clean' '
	git clone --recurse-submodules reversive/top rev &&
	git clone --recurse-submodules reversive/top fwd &&
	for d in rev fwd
	do
		echo changed >$d/sub6/sub7/sub9/file &&
		echo changed >$d/sub6/sub7/file || return 1
	done &&

	git -C rev submodule foreach --quiet --recursive \
		--reverse-traversal "git commit -q -a -m update || :" &&
	git -C rev/sub6 status --porcelain >rev.sub6 &&
	git -C rev/sub6/sub7 status --porcelain >rev.sub7 &&
	test_must_be_empty rev.sub6 &&
	test_must_be_empty rev.sub7 &&

	git -C fwd submodule foreach --quiet --recursive \
		"git commit -q -a -m update || :" &&
	git -C fwd/sub6 status --porcelain >fwd.sub6 &&
	test_file_not_empty fwd.sub6
'

test_done
