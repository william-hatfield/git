#!/bin/sh

test_description='characterize "git log -L" as a per-line commit-depth oracle

The line-depth tool will measure how many distinct commits in X..Y touch
a line that survives in Y, using the existing "git log -L" history and
merge traversal.  These tests pin what stock Git actually does, so that
the tool is built on observed behavior rather than on a reading of
line-log.c.  They exercise git only; the tool does not exist yet.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t

. "$TEST_DIRECTORY"/test-lib.sh

# Write the given lines to <path>, commit them, and tag the commit.
#   cf <tag> <path> <line>...
cf () {
	tag=$1 path=$2 &&
	shift 2 &&
	printf "%s\n" "$@" >"$path" &&
	git add "$path" &&
	test_tick &&
	git commit -q -m "$tag" &&
	git tag "$tag"
}

# Sorted, space-separated tag names of the commits "git log -L" reports
# for <lines>:<path> in <range>.  Every commit used here carries a tag.
#   touched <range> <lines> <path>
touched () {
	git log -L"$2:$3" --format=%H --no-patch "$1" >touched.raw &&
	: >touched.names &&
	while read -r oid
	do
		git describe --tags --exact-match "$oid" >>touched.names || return 1
	done <touched.raw &&
	sort touched.names | tr "\n" " " | sed "s/ $//" &&
	echo
}

# touched_is "<expected tags>" <range> <lines> <path>
touched_is () {
	expect=$1
	shift &&
	touched "$@" >actual &&
	echo "$expect" >expect &&
	test_cmp expect actual
}

test_expect_success 'empty sets: X..X dies, Y an ancestor of X is empty' '
	git init r2 &&
	(
		cd r2 &&
		cf r0 f alpha0 beta0 &&
		cf W f alpha1 beta0 &&
		cf U other u1 &&
		cf Y f alpha1 beta1 &&
		# alpha was last touched at the excluded boundary or before
		touched_is "" W..Y 1,1 f &&
		touched_is "W r0" Y 1,1 f &&
		touched_is "Y" W..Y 2,2 f &&
		test_must_fail git log -L1,1:f --format=%H --no-patch Y..Y 2>err &&
		test_grep "No commit specified" err &&
		# Y is an ancestor of W-or-later, so "Y..W" is empty
		git log -L1,1:f --format=%H --no-patch Y..W >out &&
		test_must_be_empty out
	)
'

test_expect_success 'introductions and successive edits (case 3)' '
	git init r3 &&
	(
		cd r3 &&
		cf X f anchor &&
		cf A f anchor new &&
		cf B f anchor new-v2 &&
		cf Uo other u &&
		cf C f anchor new-v3 &&
		touched_is "A" X..A 2,2 f &&
		touched_is "A B" X..B 2,2 f &&
		touched_is "B C" A..C 2,2 f &&
		touched_is "A B C" X..C 2,2 f
	)
'

test_expect_success 'existing line, distinct commits (case 4)' '
	git init r4 &&
	(
		cd r4 &&
		cf X f one keep &&
		cf A f one-a keep &&
		cf Uo other u &&
		cf B f one-b keep &&
		touched_is "A B" X..B 1,1 f &&
		touched_is "B" A..B 1,1 f
	)
'

test_expect_success 'one commit editing two lines is a single touch' '
	git init r4b &&
	(
		cd r4b &&
		cf X f l1 l2 l3 &&
		cf A f l1a l2 l3a &&
		touched_is "A" X..A 1,3 f &&
		touched_is "A" X..A 1,1 f &&
		touched_is "A" X..A 3,3 f
	)
'

test_expect_success 'per-line maximum differs from the range union (case 5)' '
	git init r5 &&
	(
		cd r5 &&
		cf X f left sep right &&
		cf A f left-a sep right &&
		cf B f left-a sep right-b &&
		touched_is "A" X..B 1,1 f &&
		touched_is "" X..B 2,2 f &&
		touched_is "B" X..B 3,3 f &&
		touched_is "A B" X..B 1,3 f &&
		touched_is "A" X..B 1,2 f &&
		touched_is "B" X..B 2,3 f &&
		cf C f left-c sep right-c &&
		touched_is "A C" X..C 1,1 f &&
		touched_is "B C" X..C 3,3 f &&
		touched_is "A B C" X..C 1,3 f
	)
'

test_expect_success 'coordinate shifts do not change the count (case 6)' '
	git init r6 &&
	(
		cd r6 &&
		cf X f above target below &&
		cf A f above new target below &&
		cf B f new target below &&
		cf C f new target-c below &&
		touched_is "C" X..C 2,2 f
	)
'

test_expect_success 'adjacent insertions do not touch the existing line' '
	git init r6b &&
	(
		cd r6b &&
		cf X f top target bottom &&
		cf A f top ins1 target bottom &&
		cf B f top ins1 target ins2 bottom &&
		touched_is "A" X..B 2,2 f &&
		touched_is "" X..B 3,3 f &&
		touched_is "B" X..B 4,4 f &&
		touched_is "" X..B 1,1 f &&
		touched_is "" X..B 5,5 f
	)
'

test_expect_success 'interior deletion: neighbours untouched, enclosing range touched' '
	git init r6c &&
	(
		cd r6c &&
		cf X f top gone bottom &&
		cf A f top bottom &&
		touched_is "" X..A 1,1 f &&
		touched_is "" X..A 2,2 f &&
		touched_is "A" X..A 1,2 f
	)
'

test_expect_success 'replacement hunk: every line inherits the hunk history (case 7)' '
	git init r7 &&
	(
		cd r7 &&
		cf X f head a0 b0 tail &&
		cf A f head a1 b0 tail &&
		cf B f head a2 b1 tail &&
		touched_is "A B" X..B 2,2 f &&
		touched_is "A B" X..B 3,3 f
	)
'

test_expect_success 'split and join inherit the parent hunk history (case 7)' '
	git init r7b &&
	(
		cd r7b &&
		cf X f head l tail &&
		cf A f head l1 tail &&
		cf B f head l1a l1b tail &&
		touched_is "A B" X..B 2,2 f &&
		touched_is "A B" X..B 3,3 f
	) &&
	git init r7c &&
	(
		cd r7c &&
		cf X f head p q tail &&
		cf A f head p1 q tail &&
		cf B f head pq tail &&
		touched_is "A B" X..B 2,2 f
	)
'

test_expect_success 'repeated text on distinct lines is tracked by position (case 8)' '
	git init r8 &&
	(
		cd r8 &&
		cf X f repeat sep repeat &&
		cf A f repeat-1 sep repeat &&
		cf B f repeat-1 sep repeat-2 &&
		touched_is "A" X..B 1,1 f &&
		touched_is "" X..B 2,2 f &&
		touched_is "B" X..B 3,3 f
	)
'

test_done
