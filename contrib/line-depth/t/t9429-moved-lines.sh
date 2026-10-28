#!/bin/sh

test_description='moved-lines: how much of a change is code that only moved

Separates lines added and removed by X..Y from those that "git diff
--color-moved" recognizes as moved blocks.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
MOVED="$CURR_DIR"/../moved-lines

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

A1="the quick brown fox jumps over the lazy dog one"
A2="the quick brown fox jumps over the lazy dog two"

test_expect_success 'a block moved within a file' '
	git init within &&
	(
		cd within &&
		cf X f head "$A1" "$A2" mid1 mid2 tail &&
		cf P f head mid1 mid2 "$A1" "$A2" brand-new-line tail &&
		expect_is "$MOVED" X..P <<-\EOF
		added 3
		removed 2
		moved_added 2
		moved_removed 2
		EOF
	)
'

test_expect_success 'a block moved to another file' '
	git init across &&
	(
		cd across &&
		cf X f head "$A1" "$A2" tail &&
		cf X2 g g1 &&
		printf "%s\n" head tail >f &&
		printf "%s\n" g1 "$A1" "$A2" >g &&
		git add f g &&
		test_tick &&
		git commit -q -m P &&
		git tag P &&
		expect_is "$MOVED" X2..P <<-\EOF
		added 2
		removed 2
		moved_added 2
		moved_removed 2
		EOF
	)
'

test_expect_success 'changes that move nothing' '
	git init plain &&
	(
		cd plain &&
		cf X f one two three &&
		cf P f one 2 three four &&
		expect_is "$MOVED" X..P <<-\EOF &&
		added 2
		removed 1
		moved_added 0
		moved_removed 0
		EOF
		expect_is "$MOVED" X..X <<-\EOF
		added 0
		removed 0
		moved_added 0
		moved_removed 0
		EOF
	)
'

test_expect_success 'short lines that change place are not moves' '
	git init short &&
	(
		cd short &&
		cf X f head one two tail &&
		cf P f head two one tail &&
		expect_is "$MOVED" X..P <<-\EOF
		added 1
		removed 1
		moved_added 0
		moved_removed 0
		EOF
	)
'

test_expect_success 'user colour configuration does not matter, paths limit the files' '
	git init config &&
	(
		cd config &&
		cf X f head "$A1" "$A2" mid1 mid2 tail &&
		cf P f head mid1 mid2 "$A1" "$A2" brand-new-line tail &&
		git config color.diff.new red &&
		git config color.diff.newMoved cyan &&
		git config color.diff.oldMoved green &&
		git config diff.colorMoved plain &&
		expect_is "$MOVED" X..P <<-\EOF &&
		added 3
		removed 2
		moved_added 2
		moved_removed 2
		EOF
		expect_is "$MOVED" X..P no-such-file <<-\EOF
		added 0
		removed 0
		moved_added 0
		moved_removed 0
		EOF
	)
'

test_expect_success 'bad input is an error with nothing on stdout' '
	git init errors &&
	(
		cd errors &&
		cf X f a &&
		cf P f b &&
		! "$MOVED" >out 2>err &&
		test_must_be_empty out &&
		! "$MOVED" no-such..P >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$MOVED" P >out 2>err &&
		test_must_be_empty out &&
		test_grep "X\.\.Y" err
	)
'

test_done
