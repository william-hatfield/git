#!/bin/sh

test_description='churn-ratio: gross lines changed by the commits of a range versus net

Gross is the lines added and deleted summed over the (non-merge) commits of
X..Y; net is the same for the single diff of X against Y.  The surplus is
rework: lines that were changed and changed again, or changed and restored.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
CHURN="$CURR_DIR"/../churn-ratio

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

test_expect_success 'rework is the surplus of gross over net' '
	git init rework &&
	(
		cd rework &&
		cf X f l1 l2 &&
		cf A f l1 l2 l3 &&
		cf B f l1 l2 l3b &&
		cf C f l1 l2 l3 &&
		expect_is "$CHURN" X..C <<-\EOF
		gross 5
		net 1
		rework 4
		EOF
	)
'

test_expect_success 'an empty range has no churn' '
	git init empty &&
	(
		cd empty &&
		cf X f l1 &&
		cf Y f l1 l2 &&
		expect_is "$CHURN" Y..Y <<-\EOF
		gross 0
		net 0
		rework 0
		EOF
	)
'

test_expect_success 'merge commits are not counted twice' '
	git init merges &&
	(
		cd merges &&
		cf X f a &&
		cf X2 other o &&
		git switch -q -c side X &&
		cf S f b &&
		git switch -q - &&
		cf D other o2 &&
		test_tick &&
		git merge -q --no-edit side &&
		git tag M &&
		expect_is "$CHURN" X2..M <<-\EOF
		gross 4
		net 4
		rework 0
		EOF
	)
'

test_expect_success 'paths limit the files, binary files are skipped' '
	git init paths &&
	(
		cd paths &&
		cf X f a &&
		cf A f a1 &&
		cf B g g1 &&
		printf "\0bin\n" >b &&
		git add b &&
		test_tick &&
		git commit -q -m C &&
		git tag C &&
		expect_is "$CHURN" X..C <<-\EOF &&
		gross 3
		net 3
		rework 0
		EOF
		expect_is "$CHURN" X..C f <<-\EOF
		gross 2
		net 2
		rework 0
		EOF
	)
'

test_expect_success 'bad input is an error with nothing on stdout' '
	git init errors &&
	(
		cd errors &&
		cf X f a &&
		cf P f b &&
		! "$CHURN" >out 2>err &&
		test_must_be_empty out &&
		! "$CHURN" no-such..P >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$CHURN" P >out 2>err &&
		test_must_be_empty out &&
		test_grep "X\.\.Y" err
	)
'

test_done
