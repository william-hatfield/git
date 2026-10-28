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

test_done
