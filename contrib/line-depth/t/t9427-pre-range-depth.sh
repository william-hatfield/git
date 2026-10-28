#!/bin/sh

test_description='pre-range-depth: how contested were the lines a range changes

For the lines of X that X..Y modifies or deletes, the largest number of
commits in W..X (the history before the range) that touched any one of them.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
PRE="$CURR_DIR"/../pre-range-depth

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

test_expect_success 'depth of the old lines over a window of earlier history' '
	git init window &&
	(
		cd window &&
		cf R f l1 s1 l2 s2 l3 &&
		cf E1 f l1 s1 l2b s2 l3 &&
		cf E2 f l1 s1 l2c s2 l3 &&
		cf E3 f l1 s1 l2c s2 l3b &&
		cf X other o &&
		cf P f l1x s1 l2d s2 l3c &&
		# l1 untouched, l2 by E1 and E2, l3 by E3
		expect_is "$PRE" R X..P <<-\EOF &&
		ranges 3
		depth 2
		EOF
		expect_is "$PRE" E1 X..P <<-\EOF &&
		ranges 3
		depth 1
		EOF
		expect_is "$PRE" E3 X..P <<-\EOF &&
		ranges 3
		depth 0
		EOF
		expect_is "$PRE" X X..P <<-\EOF
		ranges 3
		depth 0
		EOF
	)
'

test_expect_success 'a deleted file and a rename use the old side' '
	git init oldside &&
	(
		cd oldside &&
		cf R f l1 l2 l3 &&
		cf E1 f l1 l2b l3 &&
		cf R2 g g1 g2 &&
		cf E2 g g1 g2b &&
		cf X other o &&
		git rm -q f &&
		git mv g h &&
		printf "%s\n" g1 g2c >h &&
		test_tick &&
		git commit -q -a -m P &&
		git tag P &&
		# f is deleted whole (depth 1, from E1); g becomes h with line 2
		# changed: R2 created g inside the window and E2 edited it, so 2
		expect_is "$PRE" R X..P <<-\EOF &&
		ranges 2
		depth 2
		EOF
		expect_is "$PRE" R X..P f <<-\EOF
		ranges 1
		depth 1
		EOF
	)
'

test_expect_success 'added lines and untouched files have nothing to measure' '
	git init added &&
	(
		cd added &&
		cf R f l1 l2 &&
		cf X other o &&
		cf P f l1 l2 l3 &&
		expect_is "$PRE" R X..P <<-\EOF
		ranges 0
		depth 0
		EOF
	)
'

test_expect_success 'bad input is an error with nothing on stdout' '
	git init errors &&
	(
		cd errors &&
		cf X f a &&
		cf P f b &&
		! "$PRE" >out 2>err &&
		test_must_be_empty out &&
		! "$PRE" X >out 2>err &&
		test_must_be_empty out &&
		! "$PRE" no-such X..P >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$PRE" X P >out 2>err &&
		test_must_be_empty out &&
		test_grep "X\.\.Y" err
	)
'

test_done
