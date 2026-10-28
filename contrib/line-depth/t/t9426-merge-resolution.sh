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

test_expect_success 'an octopus merge is refused: remerge-diff is for two parents' '
	git init octopus &&
	(
		cd octopus &&
		cf X f a &&
		git switch -q -c b1 &&
		cf B1 g b &&
		git switch -q -c b2 X &&
		cf B2 h c &&
		tree=$(git rev-parse "B1^{tree}") &&
		test_tick &&
		O=$(git commit-tree "$tree" -p X -p B1 -p B2 -m O) &&
		git tag O "$O" &&
		! "$RESOLUTION" O >out 2>err &&
		test_must_be_empty out &&
		test_grep "two-parent" err
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

test_expect_success 'clean merges of independent random edits have no resolution, evil ones count exactly' '
	for seed in 1 2 3 4
	do
		git init rnd$seed &&
		(
			cd rnd$seed &&
			awk "BEGIN { for (i = 1; i <= 10; i++) print \"i\" i }" >a &&
			awk "BEGIN { for (i = 1; i <= 10; i++) print \"j\" i }" >b &&
			git add a b &&
			test_tick &&
			git commit -q -m base &&
			git tag base &&
			main=$(git symbolic-ref --short HEAD) &&
			RANDOM_FILE=a random_edits $seed left 3 &&
			git switch -q -c right base &&
			RANDOM_FILE=b random_edits $((seed + 50)) right 3 &&
			git switch -q "$main" &&
			test_tick &&
			git merge -q --no-edit right &&
			git tag clean &&
			expect_is "$RESOLUTION" clean <<-\EOF &&
			parents 2
			files 0
			added 0
			deleted 0
			EOF
			git reset -q --hard left3 &&
			git merge -q --no-commit --no-ff right &&
			test_seq $seed >extra &&
			git add extra &&
			test_tick &&
			git commit -q -m evil &&
			git tag evil &&
			expect_is "$RESOLUTION" evil <<-EOF
			parents 2
			files 1
			added $seed
			deleted 0
			EOF
		) || return 1
	done
'

test_expect_success 'merge.conflictStyle changes how many marker lines count as deleted' '
	git init style &&
	(
		cd style &&
		cf X f base &&
		git switch -q -c left &&
		cf L f ours &&
		git switch -q -c right X &&
		cf R f theirs &&
		git switch -q left &&
		test_must_fail git merge --no-edit right &&
		printf "%s\n" resolved >f &&
		git add f &&
		test_tick &&
		git commit -q --no-edit &&
		git tag M &&
		expect_is "$RESOLUTION" M <<-\EOF &&
		parents 2
		files 1
		added 1
		deleted 5
		EOF
		# diff3 style adds the "|||||||" marker and the base line
		git config merge.conflictStyle diff3 &&
		expect_is "$RESOLUTION" M <<-\EOF
		parents 2
		files 1
		added 1
		deleted 7
		EOF
	)
'

test_done
