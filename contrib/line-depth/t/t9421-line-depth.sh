#!/bin/sh

test_description='line-depth: maximum per-line commit depth in a revision range

For each line of <file> in the tip of <X..Y> within <start>,<end>, count the
distinct commits in X..Y that touch it (as "git log -L" tracks it), and print
the largest count.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
LINE_DEPTH="$CURR_DIR"/../line-depth

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

# depth_is <expected> <line-depth arguments>
depth_is () {
	echo "$1" >expect &&
	shift &&
	"$LINE_DEPTH" "$@" >actual &&
	test_cmp expect actual
}

test_expect_success 'depth of a single line counts distinct commits' '
	git init single &&
	(
		cd single &&
		cf X f anchor &&
		cf A f anchor new &&
		cf B f anchor new-v2 &&
		cf Uo other u &&
		cf C f anchor new-v3 &&
		depth_is 1 X..A 2,2:f &&
		depth_is 2 X..B 2,2:f &&
		depth_is 2 A..C 2:f &&
		depth_is 3 X..C 2,2:f
	)
'

test_expect_success 'a line no commit in the range touches has depth 0' '
	git init untouched &&
	(
		cd untouched &&
		cf X f alpha beta &&
		cf Y f alpha beta-y &&
		depth_is 0 X..Y 1,1:f
	)
'

test_expect_success 'a range is the maximum per-line depth, not the union' '
	git init maximum &&
	(
		cd maximum &&
		cf X f left sep right &&
		cf A f left-a sep right &&
		cf B f left-a sep right-b &&
		depth_is 1 X..B 1,3:f &&
		cf C f left-c sep right-c &&
		depth_is 2 X..C 1,3:f
	)
'

test_expect_success 'a git failure is an error, never a count of zero' '
	git init failure &&
	(
		cd failure &&
		cf X f one &&
		cf Y f two &&
		! "$LINE_DEPTH" X..Y 1,1:missing >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$LINE_DEPTH" no-such-rev..Y 1,1:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err
	)
'

test_expect_success 'an empty revision set has depth 0 once the request validates' '
	git init empty &&
	(
		cd empty &&
		cf X f a b &&
		cf Y f a b2 &&
		depth_is 0 X..X 1,1:f &&
		depth_is 0 Y..X 2,2:f &&
		! "$LINE_DEPTH" X..X 1,1:missing >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$LINE_DEPTH" X..X 3,3:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$LINE_DEPTH" no-such..no-such 1,1:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err
	)
'

test_expect_success 'max:<file> is the maximum depth over every line of the file' '
	git init whole &&
	(
		cd whole &&
		cf X f left sep right &&
		cf A f left-a sep right &&
		cf B f left-a sep right-b &&
		depth_is 1 X..B max:f &&
		cf C f left-c sep right-c &&
		depth_is 2 X..C max:f &&
		depth_is 0 C..C max:f
	)
'

test_expect_success 'max:<file> counts a line without a trailing newline' '
	git init noeol &&
	(
		cd noeol &&
		printf "a\nb" >f &&
		git add f &&
		test_tick &&
		git commit -q -m X &&
		git tag X &&
		printf "a\nb2" >f &&
		git commit -q -a -m A &&
		git tag A &&
		printf "a\nb3" >f &&
		git commit -q -a -m B &&
		git tag B &&
		depth_is 2 X..B max:f &&
		depth_is 2 X..B 2,2:f
	)
'

test_expect_success 'an existing empty file has maximum 0, an explicit range on it is an error' '
	git init emptyfile &&
	(
		cd emptyfile &&
		cf X f a &&
		: >f &&
		git commit -q -a -m Y &&
		git tag Y &&
		depth_is 0 X..Y max:f &&
		! "$LINE_DEPTH" X..Y 1,1:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err
	)
'

test_expect_success 'a file missing at the tip is an error, not an empty file' '
	git init gone &&
	(
		cd gone &&
		cf X f a &&
		git rm -q f &&
		test_tick &&
		git commit -q -m Y &&
		git tag Y &&
		! "$LINE_DEPTH" X..Y max:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err
	)
'

test_expect_success 'a line outside the file is an error, as for git log -L' '
	git init bounds &&
	(
		cd bounds &&
		cf X f l1 l2 l3 &&
		cf A f l1 l2a l3 &&
		! "$LINE_DEPTH" X..A 4,4:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$LINE_DEPTH" X..A 0,2:f >out 2>err &&
		test_must_be_empty out
	)
'

test_expect_success 'a binary file has no lines to measure' '
	git init binary &&
	(
		cd binary &&
		cf X f one &&
		printf "a\0b\n" >bin &&
		git add bin &&
		test_tick &&
		git commit -q -m Y &&
		git tag Y &&
		! "$LINE_DEPTH" X..Y max:bin >out 2>err &&
		test_must_be_empty out &&
		test_grep -i binary err
	)
'

test_expect_success 'paths are relative to the working directory' '
	git init subdir &&
	(
		cd subdir &&
		mkdir sub &&
		cf X sub/f a b &&
		cf A sub/f a b2 &&
		cd sub &&
		depth_is 1 X..A 2,2:f &&
		depth_is 1 X..A max:f
	)
'

test_done
