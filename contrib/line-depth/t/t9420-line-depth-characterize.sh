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

# Merge commit built from a tree rather than by "git merge", so any result
# can be produced.  The tree holds only a file "f" with <content>.
#   mk_merge <tag> <content> <parent>...
mk_merge () {
	tag=$1 content=$2 &&
	shift 2 &&
	blob=$(printf "%s\n" "$content" | git hash-object -w --stdin) &&
	tree=$(printf "100644 blob %s\tf\n" "$blob" | git mktree) &&
	args= &&
	for p
	do
		args="$args -p $(git rev-parse "$p")" || return 1
	done &&
	test_tick &&
	c=$(git commit-tree $args -m "$tag" "$tree") &&
	git tag "$tag" "$c"
}

test_expect_success 'merge parents: a parent matching the merge is followed alone (case 9)' '
	git init r9 &&
	(
		cd r9 &&
		cf X f a &&
		cf P f b &&
		git switch -q -c side X &&
		cf Q f c &&
		cf Qb f b &&
		mk_merge Mb b P Q &&
		mk_merge Mc c P Q &&
		mk_merge Mbb b P Qb &&
		# matches the first parent: follow P, omit the merge and Q
		touched_is "P" X..Mb 1,1 f &&
		# matches the second parent: follow Q, omit the merge and P
		touched_is "Q" X..Mc 1,1 f &&
		# both parents match the merge: only the first is followed
		touched_is "P" X..Mbb 1,1 f
	)
'

test_expect_success 'merge parents: a merge differing from every parent is a touch (case 9)' '
	git init r9b &&
	(
		cd r9b &&
		cf X f a &&
		cf P f b &&
		git switch -q -c side X &&
		cf Q f c &&
		mk_merge Md d P Q &&
		touched_is "Md P Q" X..Md 1,1 f
	)
'

test_expect_success 'octopus merge follows the same unchanged-parent rule (case 9)' '
	git init r9c &&
	(
		cd r9c &&
		cf X f a &&
		cf P f b &&
		git switch -q -c side1 X &&
		cf Q f c &&
		git switch -q -c side2 X &&
		cf Rr f d &&
		mk_merge Ob b P Q Rr &&
		mk_merge Oe e P Q Rr &&
		touched_is "P" X..Ob 1,1 f &&
		touched_is "Oe P Q Rr" X..Oe 1,1 f
	)
'

test_expect_success 'a reverted merged change counts for the surviving line (case 10)' '
	git init r10 &&
	(
		cd r10 &&
		cf X f old x0 &&
		git switch -q -c side &&
		cf C f new x0 &&
		git switch -q - &&
		cf D other o1 &&
		test_tick &&
		git merge -q --no-edit side &&
		git tag M &&
		test_tick &&
		git revert --no-edit C >/dev/null &&
		git tag R &&
		cf E f old x1 &&
		# the simple merge is omitted: it matches the side parent
		touched_is "C R" X..R 1,1 f &&
		touched_is "C R" X..E 1,1 f &&
		touched_is "E" X..E 2,2 f &&
		# the final diff of X..E leaves line 1 alone, yet it has depth 2
		git diff X E -- f >diff.out &&
		test_grep "^-x0" diff.out &&
		test_grep "^+x1" diff.out &&
		test_grep ! "^[-+]old" diff.out
	)
'

test_expect_success 'boundary: the base tip excludes merged-in upstream work (case 11)' '
	git init r11 &&
	(
		cd r11 &&
		cf R f v0 sep s0 &&
		cf U f v1 sep s0 &&
		git switch -q -c topic R &&
		cf S1 f v0 sep s1 &&
		test_tick &&
		git merge -q --no-edit U &&
		git tag M &&
		cf T f v2 sep s1 &&
		touched_is "T" U..T 1,1 f &&
		touched_is "T U" R..T 1,1 f
	)
'

test_expect_success 'boundary: fork versus ancestor base (case 11)' '
	git init r11b &&
	(
		cd r11b &&
		cf R f l0 &&
		cf X other x &&
		git switch -q -c topic R &&
		cf S f l1 &&
		cf Y f l2 &&
		touched_is "S Y" X..Y 1,1 f &&
		touched_is "S Y" R..Y 1,1 f &&
		touched_is "Y" S..Y 1,1 f
	)
'

test_expect_success 'rename detection follows or stops at a rename (case 12)' '
	git init r12 &&
	(
		cd r12 &&
		cf R0 old one &&
		cf E1 old two &&
		cf E2 old three &&
		git mv old new &&
		test_tick &&
		git commit -q -m Rn &&
		git tag Rn &&
		git -c diff.renames=true log -L1,1:new --format=%H --no-patch R0..Rn >on &&
		git -c diff.renames=false log -L1,1:new --format=%H --no-patch R0..Rn >off &&
		test_line_count = 2 on &&
		test_line_count = 1 off &&
		git rev-parse Rn >expect &&
		test_cmp expect off
	)
'

test_expect_success 'a file created inside the range is touched by its creator' '
	git init r13 &&
	(
		cd r13 &&
		cf X f a &&
		cf A g n1 n2 &&
		cf B g n1 n2b &&
		touched_is "A" X..B 1,1 g &&
		touched_is "A B" X..B 2,2 g
	)
'

test_expect_success 'mode, whitespace and empty commits' '
	git init r14 &&
	(
		cd r14 &&
		cf X f l1 l2 &&
		git update-index --chmod=+x f &&
		test_tick &&
		git commit -q -m Mode &&
		git tag Mode &&
		test_tick &&
		git commit -q --allow-empty -m Empty &&
		git tag Empty &&
		cf Ws f "l1 " l2 &&
		# a mode-only change and an empty commit do not touch a line;
		# a whitespace-only edit does
		touched_is "Ws" X..Ws 1,1 f &&
		touched_is "" X..Ws 2,2 f
	)
'

test_expect_success 'paths are relative to the working directory' '
	git init r15 &&
	(
		cd r15 &&
		mkdir sub &&
		cf X sub/f a b &&
		cf A sub/f a b2 &&
		cd sub &&
		touched_is "A" X..A 2,2 f
	)
'

test_expect_success 'revisions may be spelled as annotated tags or abbreviated ids' '
	git init r16 &&
	(
		cd r16 &&
		cf X f one &&
		cf Y f two &&
		git tag -a -m annotated AnnY Y &&
		git log -L1,1:f --format=%H --no-patch X..Y >expect &&
		git log -L1,1:f --format=%H --no-patch X..AnnY >actual &&
		test_cmp expect actual &&
		short=$(git rev-parse --short Y) &&
		git log -L1,1:f --format=%H --no-patch X..$short >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'binary files are accepted as lines of bytes' '
	git init r17 &&
	(
		cd r17 &&
		printf "a\0b\nc\n" >bin &&
		git add bin &&
		test_tick &&
		git commit -q -m X &&
		git tag X &&
		printf "a\0b\nd\n" >bin &&
		git commit -q -a -m Y &&
		git tag Y &&
		git log -L2,2:bin --format=%H --no-patch X..Y >actual &&
		git rev-parse Y >expect &&
		test_cmp expect actual
	)
'

test_expect_success 'numeric range forms accepted and rejected by -L' '
	git init r18 &&
	(
		cd r18 &&
		cf X f l1 l2 l3 l4 l5 &&
		cf A f l1 l2a l3 l4 l5a &&
		git log -L2,5:f --format=%H --no-patch X..A >expect &&
		test_line_count = 1 expect &&
		# reversed endpoints are swapped, an end past EOF is clamped
		git log -L5,2:f --format=%H --no-patch X..A >actual &&
		test_cmp expect actual &&
		git log -L2,99:f --format=%H --no-patch X..A >actual &&
		test_cmp expect actual &&
		# omitted start is line 1
		git log -L,2:f --format=%H --no-patch X..A >actual &&
		test_cmp expect actual &&
		# a start past EOF, zero, and an empty range are errors
		test_must_fail git log -L6:f --format=%H --no-patch X..A 2>err &&
		test_grep "has only 5 lines" err &&
		test_must_fail git log -L0,3:f --format=%H --no-patch X..A 2>err &&
		test_grep "invalid line number" err &&
		test_must_fail git log -L3,+0:f --format=%H --no-patch X..A 2>err &&
		test_grep "invalid empty range" err
	)
'

test_expect_success 'an existing empty file has no line to select' '
	git init r19 &&
	(
		cd r19 &&
		: >e &&
		git add e &&
		test_tick &&
		git commit -q -m empty &&
		test_must_fail git log -L1,1:e --format=%H --no-patch HEAD 2>err &&
		test_grep "has only 0 lines" err
	)
'

test_done
