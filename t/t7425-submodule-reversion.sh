#!/bin/sh
#
# Copyright (c) 2026 William Hatfield
#

test_description='Test "git submodule foreach --reversive"

This test suite validates the --reversive flag and its constituent options:
--recursive, --reverse-traversal, and --append-superproject. Tests confirm
flags are correctly parsed and set non-zero integral values. Additional tests
verify post-order traversal, superproject inclusion, and flag combinations.
The --reversive flag is shorthand for: --recursive --reverse-traversal
--append-superproject.
'

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

# Helper: create content and initial commit in a submodule
# Usage: create_submodule_content <name> <content>
create_submodule_content () {
	echo "$2" >"$1/file" &&
	git -C "$1" add file &&
	test_tick &&
	git -C "$1" commit -m "$1 commit"
}

# Helper: add submodules to a parent and commit
# Usage: add_submodules <parent> <child1> [child2 ...]
add_submodules () {
	parent=$1 &&
	shift &&
	for child in "$@"; do
		git -C "$parent" submodule add ../"$child" "$child" || return 1
	done &&
	test_tick &&
	git -C "$parent" commit -m "add $*"
}

test_expect_success 'setup - enable local submodules' '
	git config --global protocol.file.allow always
'

test_expect_success 'setup reversive sandbox (full multi-branch tree)' '
	mkdir reversive &&
	(
		# Tree structure created in this sandbox:
		#
		#     top
		#     ├── sub0
		#     │
		#     ├── sub1
		#     │   └── sub2
		#     │
		#     ├── sub3
		#     │   ├── sub4
		#     │   └── sub5
		#     │
		#     └── sub6
		#         └── sub7
		#             ├── sub8
		#             └── sub9
		#
		# This structure provides:
		#   - Four top‑level siblings (sub0, sub1, sub3, sub6)
		#   - Mixed branch depths (1‑deep, 2‑deep, 3‑deep)
		#   - Multiple nested sibling sets (sub4+5 and sub8+9)
		#   - A leaf‑only sibling (sub0)
		#   - Ideal coverage for traversal tests

		cd reversive &&

		# Create all repositories
		test_create_repo top &&
		test_create_repo sub0 &&
		test_create_repo sub1 &&
		test_create_repo sub2 &&
		test_create_repo sub3 &&
		test_create_repo sub4 &&
		test_create_repo sub5 &&
		test_create_repo sub6 &&
		test_create_repo sub7 &&
		test_create_repo sub8 &&
		test_create_repo sub9 &&

		# Create leaf submodules first (no children)
		create_submodule_content sub0 zero &&
		create_submodule_content sub2 two &&
		create_submodule_content sub4 four &&
		create_submodule_content sub5 five &&
		create_submodule_content sub8 eight &&
		create_submodule_content sub9 nine &&

		# Build sub1 branch (sub1 -> sub2)
		create_submodule_content sub1 one &&
		add_submodules sub1 sub2 &&

		# Build sub3 branch (sub3 -> sub4, sub5)
		create_submodule_content sub3 three &&
		add_submodules sub3 sub4 sub5 &&

		# Build sub7 (sub7 -> sub8, sub9)
		create_submodule_content sub7 seven &&
		add_submodules sub7 sub8 sub9 &&

		# Build sub6 branch (sub6 -> sub7)
		create_submodule_content sub6 six &&
		add_submodules sub6 sub7 &&

		# Build top (top -> sub0, sub1, sub3, sub6)
		create_submodule_content top root &&
		add_submodules top sub0 sub1 sub3 sub6 &&
		git -C top submodule update --init --recursive
	)
'

test_expect_success '--recursive parses and prints(runs), existing behavior' '
	(
		cd reversive/top &&
		git submodule --quiet foreach --recursive "echo \$displaypath"
	) >actual &&

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

test_expect_failure '--recursive and --reverse-traversal parses' '
	(
		cd reversive/top &&
		git submodule foreach --recursive --reverse-traversal "true"
	)
'

test_expect_failure '--recursive and --reverse-traversal runs' '
	(
		cd reversive/top &&
		git submodule --quiet foreach --recursive \
			--reverse-traversal "echo \$displaypath"
	) >actual &&

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

test_expect_failure '--recursive and --append-superproject parses' '
	(
		cd reversive/top &&
		git submodule foreach --recursive --append-superproject "true"
	)
'

test_expect_failure '--recursive and --append-superproject runs' '
	(
		cd reversive/top &&
		git submodule --quiet foreach --recursive \
			--append-superproject "echo \$displaypath"
	) >actual &&

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
../top
EOF

	test_cmp expect actual
'

test_expect_failure '--reverse-traversal and --append-superproject parses' '
	(
		cd reversive/top &&
		git submodule foreach \
			--recursive --reverse-traversal --append-superproject "true"
	)
'

test_expect_failure '--reverse-traversal and --append-superproject runs' '
	(
		cd reversive/top &&
		git submodule --quiet foreach --recursive \
			--reverse-traversal --append-superproject "echo \$displaypath"
	) >actual &&

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
../top
EOF

	test_cmp expect actual
'

test_expect_failure '--reversive parses' '
	(
		cd reversive/top &&
		git submodule foreach --reversive "true"
	)
'

test_expect_failure '--reversive runs' '
	(
		cd reversive/top &&
		git submodule --quiet foreach --reversive "echo \$displaypath"
	) >actual &&

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
../top
EOF

	test_cmp expect actual
'

test_expect_failure '--reversive stops on command failure' '
	(
		cd reversive/top &&
		git submodule foreach --reversive "true" &&
		test_must_fail git submodule foreach --reversive \
			"test \$name != sub7 || exit 1"
	)
'

test_expect_failure '--append-superproject with no submodules runs only superproject' '
	test_create_repo empty_repo &&
	(
		cd empty_repo &&
		git submodule --quiet foreach --append-superproject \
			"echo \$displaypath"
	) >actual &&

	cat >expect <<-\EOF &&
../empty_repo
EOF

	test_cmp expect actual
'

test_expect_failure '--append-superproject sets all expected variables' '
	(
		cd reversive/top &&
		git submodule --quiet foreach --append-superproject \
			"echo name=\$name path=\$path displaypath=\$displaypath" |
			tail -n 1
	) >actual &&

	cat >expect <<-\EOF &&
name=top path=../top displaypath=../top
EOF

	test_cmp expect actual
'

test_expect_failure '--append-superproject from nested submodule appends correct superproject' '
	(
		cd reversive/top/sub6 &&
		git submodule --quiet foreach --recursive --append-superproject \
			"echo \$displaypath"
	) >actual &&

	cat >expect <<-\EOF &&
sub7
sub7/sub8
sub7/sub9
../sub6
EOF

	test_cmp expect actual
'

test_expect_failure '--quiet suppresses Entering message for superproject' '
	(
		cd reversive/top &&
		git submodule foreach --quiet --append-superproject "true"
	) >actual 2>&1 &&

	! grep "Entering" actual
'

test_done
