#!/bin/sh

test_description='forward-survival: which lines of X were gone by Y

Uses "git blame --reverse" to follow the lines of the changed files forward
from X and counts how many did not survive to Y, and at how many different
points of history the last of them were still present.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
SURVIVAL="$CURR_DIR"/../forward-survival

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

test_expect_success 'lines removed at different points of history' '
	git init removed &&
	(
		cd removed &&
		cf X f l1 l2 l3 l4 &&
		cf A f l1 l3 l4 &&
		cf B f l1 l3 l4b &&
		# l2 was last seen at X, l4 at A; l1 and l3 survive
		expect_is "$SURVIVAL" X..B <<-\EOF
		files 1
		lines 4
		removed 2
		removal_points 2
		EOF
	)
'

test_expect_success 'removed at one point counts one point' '
	git init onepoint &&
	(
		cd onepoint &&
		cf X f l1 s1 l2 s2 l3 &&
		cf A f l1x s1 l2x s2 l3 &&
		expect_is "$SURVIVAL" X..A <<-\EOF
		files 1
		lines 5
		removed 2
		removal_points 1
		EOF
	)
'

test_expect_success 'a deleted file, a pure rename, and an untouched file' '
	git init files &&
	(
		cd files &&
		cf X f l1 l2 l3 &&
		cf X2 g g1 g2 &&
		cf X3 other o &&
		git rm -q f &&
		git mv g h &&
		test_tick &&
		git commit -q -m P &&
		git tag P &&
		expect_is "$SURVIVAL" X3..P <<-\EOF
		files 2
		lines 5
		removed 3
		removal_points 1
		EOF
	)
'

test_expect_success 'additions alone remove nothing' '
	git init added &&
	(
		cd added &&
		cf X f l1 l2 &&
		cf A f l1 l2 l3 &&
		expect_is "$SURVIVAL" X..A <<-\EOF
		files 1
		lines 2
		removed 0
		removal_points 0
		EOF
	)
'

test_expect_success 'bad input is an error with nothing on stdout' '
	git init errors &&
	(
		cd errors &&
		cf X f a &&
		cf P f b &&
		! "$SURVIVAL" >out 2>err &&
		test_must_be_empty out &&
		! "$SURVIVAL" no-such..P >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$SURVIVAL" P >out 2>err &&
		test_must_be_empty out &&
		test_grep "X\.\.Y" err
	)
'

test_expect_success 'works from a subdirectory, with paths relative to it' '
	git init subdir &&
	(
		cd subdir &&
		mkdir sub &&
		cf X sub/f l1 l2 l3 &&
		cf A sub/f l1 l3 &&
		cd sub &&
		expect_is "$SURVIVAL" X..A <<-\EOF &&
		files 1
		lines 3
		removed 1
		removal_points 1
		EOF
		expect_is "$SURVIVAL" X..A f <<-\EOF
		files 1
		lines 3
		removed 1
		removal_points 1
		EOF
	)
'

test_done
