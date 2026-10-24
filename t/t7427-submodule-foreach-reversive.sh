#!/bin/sh
#
# Copyright (c) 2026 William Hatfield
#

test_description='git submodule foreach --reverse-traversal, --include-superproject and --reversive

Check that --reverse-traversal visits submodules in the reverse of their
usual order, and that, together with --recursive, each submodule is
visited after the submodules nested in it. Check that
--include-superproject also runs the command in the superproject, after
all the submodules, and that --reversive is a shorthand for all three of
these options.
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

test_expect_success '--include-superproject runs the command in the superproject last' '
	git -C reversive/top submodule --quiet foreach --recursive \
		--include-superproject "echo \$displaypath" >actual &&
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
	top
	EOF
	test_cmp expect actual
'

test_expect_success '--include-superproject combines with --reverse-traversal' '
	git -C reversive/top submodule --quiet foreach --recursive \
		--reverse-traversal --include-superproject \
		"echo \$displaypath" >actual &&
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
	top
	EOF
	test_cmp expect actual
'

test_expect_success '--include-superproject announces the superproject' '
	git -C reversive/top submodule foreach --include-superproject \
		true >out &&
	test_grep "^Entering .top.$" out &&
	git -C reversive/top submodule foreach --quiet \
		--include-superproject true >out &&
	test_grep ! Entering out
'

test_expect_success '--include-superproject in a repository without submodules' '
	test_create_repo "no subs" &&
	git -C "no subs" submodule --quiet foreach --include-superproject \
		"echo \"[\$displaypath]\"" >actual &&
	echo "[no subs]" >expect &&
	test_cmp expect actual
'

test_expect_success '--include-superproject uses the repository it is run in' '
	git -C reversive/top/sub6 submodule --quiet foreach --recursive \
		--include-superproject "echo \$displaypath" >actual &&
	cat >expect <<-\EOF &&
	sub7
	sub7/sub8
	sub7/sub9
	sub6
	EOF
	test_cmp expect actual
'

test_expect_success '--include-superproject runs from a subdirectory at the top level' '
	mkdir -p reversive/top/dir &&
	git -C reversive/top/dir submodule --quiet foreach \
		--include-superproject "pwd -P" >out &&
	tail -n 1 out >actual &&
	(cd reversive/top && pwd -P) >expect &&
	test_cmp expect actual
'

test_expect_success '--include-superproject sets only $displaypath and keeps the rest of the environment' '
	git -C "no subs" submodule --quiet foreach --include-superproject \
		"echo \"[\$displaypath][\$name][\$sm_path][\$sha1][\$toplevel]\"" \
		>actual &&
	echo "[no subs][][][][]" >expect &&
	test_cmp expect actual &&

	write_script nested-foreach <<-\EOF &&
	git submodule --quiet foreach --include-superproject \
		'\''printf "%s|%s|%s|%s\n" "$displaypath" "$sm_path" "$sha1" "$toplevel"'\''
	EOF
	git -C reversive/top submodule --quiet foreach \
		"if test \"\$name\" = sub0; then \"$TRASH_DIRECTORY/nested-foreach\"; fi" \
		>actual &&
	sub0_oid=$(git -C reversive/top rev-parse HEAD:sub0) &&
	top=$(cd reversive/top && pwd -P) &&
	echo "sub0|sub0|$sub0_oid|$top" >expect &&
	test_cmp expect actual
'

test_expect_success '--include-superproject preserves a detached worktree' '
	git clone --bare reversive/top detached.git &&
	mkdir detached &&
	(
		cd detached &&
		GIT_DIR="$(pwd)/../detached.git" &&
		GIT_WORK_TREE="$(pwd)" &&
		export GIT_DIR GIT_WORK_TREE &&
		git checkout --quiet &&
		git submodule update --init &&
		git submodule --quiet foreach --include-superproject \
			"git rev-parse --show-toplevel" >../actual
	) &&
	(
		cd detached &&
		for sub in sub0 sub1 sub3 sub6
		do
			(cd "$sub" && pwd -P) || return 1
		done &&
		pwd -P
	) >expect &&
	test_cmp expect actual
'

test_expect_success '--include-superproject preserves the selected index' '
	git clone --recurse-submodules reversive/top index-super &&
	cp index-super/.git/index index-super/custom-index &&
	echo content >index-super/alternate-file &&
	GIT_INDEX_FILE=custom-index git -C index-super add alternate-file &&
	mkdir index-super/dir &&
	for dir in index-super index-super/dir
	do
		GIT_INDEX_FILE=custom-index git -C $dir submodule --quiet \
			foreach --include-superproject \
			"if test \"\$displaypath\" = index-super; then
				git ls-files --error-unmatch alternate-file
			else
				test -z \"\$GIT_INDEX_FILE\"
			fi" >actual &&
		echo alternate-file >expect &&
		test_cmp expect actual || return 1
	done &&
	test_must_fail git -C index-super ls-files --error-unmatch \
		alternate-file >/dev/null 2>&1
'

test_expect_success '--include-superproject commits from the selected index' '
	cp index-super/.git/index default-index-before &&
	test_tick &&
	GIT_INDEX_FILE=custom-index git -C index-super submodule --quiet \
		foreach --include-superproject \
		"if test \"\$displaypath\" = index-super; then
			git commit -q -m alternate-index
		else
			test -z \"\$GIT_INDEX_FILE\"
		fi" &&
	git -C index-super show HEAD:alternate-file >actual &&
	echo content >expect &&
	test_cmp expect actual &&
	test_cmp_bin default-index-before index-super/.git/index
'

test_expect_success '--include-superproject does not run after a failure' '
	test_must_fail git -C reversive/top submodule --quiet foreach \
		--recursive --reverse-traversal --include-superproject \
		"echo \$displaypath; test \$name != sub8" >actual 2>err &&
	cat >expect <<-\EOF &&
	sub6/sub7/sub9
	sub6/sub7/sub8
	EOF
	test_cmp expect actual
'

test_expect_success '--include-superproject reports a failing superproject' '
	test_must_fail git -C reversive/top submodule --quiet foreach \
		--include-superproject "test \$displaypath != top" 2>err &&
	test_grep "command failed in the superproject" err
'

test_expect_success 'committing in the submodules and the superproject leaves nothing modified' '
	git clone --recurse-submodules reversive/top full &&
	echo changed >full/file &&
	echo changed >full/sub0/file &&
	echo changed >full/sub3/sub5/file &&
	echo changed >full/sub6/sub7/sub9/file &&
	git -C full submodule foreach --quiet --recursive \
		--reverse-traversal --include-superproject \
		"git commit -q -a -m \"update \$displaypath\" || :" &&
	git -C full status --porcelain >actual &&
	test_must_be_empty actual &&
	for path in sub0 sub3/sub5 sub3 sub6/sub7/sub9 sub6/sub7 sub6
	do
		case "$path" in
		*/*) parent=${path%/*} && child=${path##*/} ;;
		*) parent=. && child=$path ;;
		esac &&
		current=$(git -C "full/$path" rev-parse HEAD) &&
		original=$(git -C "reversive/top/$path" rev-parse HEAD) &&
		test "$current" != "$original" &&
		echo "$current" >expect &&
		git -C "full/$parent" rev-parse "HEAD:$child" >actual &&
		test_cmp expect actual || return 1
	done
'

test_expect_success '--reversive is --recursive --reverse-traversal --include-superproject' '
	git -C reversive/top submodule --quiet foreach --recursive \
		--reverse-traversal --include-superproject \
		"echo \$displaypath" >expect &&
	git -C reversive/top submodule --quiet foreach --reversive \
		"echo \$displaypath" >actual &&
	test_cmp expect actual
'

test_done
