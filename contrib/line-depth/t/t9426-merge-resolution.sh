#!/bin/sh

test_description='merge-resolution: the hand edits recorded in a merge commit

The difference between a merge commit and an automatic re-merge of its
parents: zero for a clean merge, and the conflict resolution plus any extra
change otherwise.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
RESOLUTION="$CURR_DIR"/../merge-resolution

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

test_expect_success 'a clean merge has no resolution' '
	git init clean &&
	(
		cd clean &&
		cf X f a1 a2 &&
		cf X2 g b &&
		git switch -q -c left X2 &&
		cf L f a1x a2 &&
		git switch -q -c right X2 &&
		cf R g b2 &&
		git switch -q left &&
		test_tick &&
		git merge -q --no-edit right &&
		git tag M &&
		expect_is "$RESOLUTION" M <<-\EOF
		parents 2
		files 0
		added 0
		deleted 0
		EOF
	)
'

test_expect_success 'a conflict resolved by hand' '
	git init conflict &&
	(
		cd conflict &&
		cf X f a1 a2 &&
		git switch -q -c left &&
		cf L f a1L a2 &&
		git switch -q -c right X &&
		cf R f a1R a2 &&
		git switch -q left &&
		test_must_fail git merge --no-edit right &&
		printf "%s\n" a1M a2 >f &&
		git add f &&
		test_tick &&
		git commit -q --no-edit &&
		git tag M &&
		# the conflict block: markers, ours, separator, theirs, markers
		expect_is "$RESOLUTION" M <<-\EOF
		parents 2
		files 1
		added 1
		deleted 5
		EOF
	)
'

test_expect_success 'a change made while merging, without any conflict' '
	git init evil &&
	(
		cd evil &&
		cf X f a &&
		git switch -q -c left &&
		cf L f aL &&
		git switch -q -c right X &&
		cf R g b &&
		git switch -q left &&
		git merge -q --no-commit --no-ff right &&
		printf "%s\n" e1 e2 >extra &&
		git add extra &&
		test_tick &&
		git commit -q -m M &&
		git tag M &&
		expect_is "$RESOLUTION" M <<-\EOF
		parents 2
		files 1
		added 2
		deleted 0
		EOF
	)
'

test_expect_success 'bad input is an error with nothing on stdout' '
	git init errors &&
	(
		cd errors &&
		cf X f a &&
		cf P f b &&
		! "$RESOLUTION" >out 2>err &&
		test_must_be_empty out &&
		! "$RESOLUTION" no-such >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$RESOLUTION" P >out 2>err &&
		test_must_be_empty out &&
		test_grep "not a merge" err
	)
'

test_done
