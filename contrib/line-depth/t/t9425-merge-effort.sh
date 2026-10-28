#!/bin/sh

test_description='merge-effort: how hard merging two commits would be

Reports divergence, the files changed on both sides, and the conflicts that
"git merge-tree --write-tree" finds, without touching the work tree.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
EFFORT="$CURR_DIR"/../merge-effort

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

test_expect_success 'a clean merge of changes to different files' '
	git init clean &&
	(
		cd clean &&
		cf X f a1 a2 &&
		cf X2 g b1 b2 &&
		git switch -q -c left X2 &&
		cf L1 f a1x a2 &&
		git switch -q -c right X2 &&
		cf R1 g b1 b2x &&
		cf R2 h c &&
		expect_is "$EFFORT" L1 R2 <<-\EOF
		merge_bases 1
		left_only 1
		right_only 2
		files_left 1
		files_right 2
		files_both 0
		conflicts 0
		EOF
	)
'

test_expect_success 'conflicting edits are counted per file' '
	git init conflicts &&
	(
		cd conflicts &&
		cf X f a1 a2 &&
		cf X2 g b1 b2 &&
		git switch -q -c left X2 &&
		printf "%s\n" a1L a2 >f &&
		printf "%s\n" b1L b2 >g &&
		cf L1 f a1L a2 &&
		cf L2 g b1L b2 &&
		git switch -q -c right X2 &&
		cf R1 f a1R a2 &&
		cf R2 g b1R b2 &&
		cf R3 h c &&
		expect_is "$EFFORT" L2 R3 <<-\EOF
		merge_bases 1
		left_only 2
		right_only 3
		files_left 2
		files_right 3
		files_both 2
		conflicts 2
		EOF
	)
'

test_expect_success 'a criss-cross history has more than one merge base' '
	git init crisscross &&
	(
		cd crisscross &&
		cf X f a b &&
		cf X2 g g1 &&
		git switch -q -c a X2 &&
		cf A1 f a1 b &&
		git switch -q -c b X2 &&
		cf B1 g g2 &&
		git switch -q a &&
		test_tick &&
		git merge -q --no-edit B1 &&
		git tag A2 &&
		git switch -q b &&
		test_tick &&
		git merge -q --no-edit A1 &&
		git tag B2 &&
		expect_is "$EFFORT" A2 B2 <<-\EOF
		merge_bases 2
		left_only 1
		right_only 1
		files_left 1
		files_right 1
		files_both 1
		conflicts 0
		EOF
	)
'

test_expect_success 'the work tree and refs are left alone' '
	git init untouched &&
	(
		cd untouched &&
		cf X f a &&
		git switch -q -c left &&
		cf L f aL &&
		git switch -q -c right X &&
		cf R f aR &&
		git rev-parse HEAD >../head.before &&
		git for-each-ref >../refs.before &&
		git status --porcelain >../status.before &&
		"$EFFORT" L R >../out &&
		git rev-parse HEAD >../head.after &&
		git for-each-ref >../refs.after &&
		git status --porcelain >../status.after &&
		test_cmp ../head.before ../head.after &&
		test_cmp ../refs.before ../refs.after &&
		test_cmp ../status.before ../status.after &&
		grep "^conflicts 1$" ../out
	)
'

test_expect_success 'bad input is an error with nothing on stdout' '
	git init errors &&
	(
		cd errors &&
		cf X f a &&
		git switch -q --orphan other &&
		cf O f o &&
		! "$EFFORT" >out 2>err &&
		test_must_be_empty out &&
		! "$EFFORT" X >out 2>err &&
		test_must_be_empty out &&
		! "$EFFORT" X no-such >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$EFFORT" X O >out 2>err &&
		test_must_be_empty out &&
		test_grep "merge base" err
	)
'

test_done
