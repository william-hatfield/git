#!/bin/sh

test_description='line-depth --strategy: every pruning strategy equals the per-line oracle'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
LINE_DEPTH="$CURR_DIR"/../line-depth

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

# Largest "git log -L" depth over single lines 1..n of f; stops on any failure.
#   oracle <flags> <range> <n>
oracle () {
	o_best=0
	o_i=1
	while test "$o_i" -le "$3"
	do
		o_n=$(git log -L$o_i,$o_i:f $1 --format=%H --no-patch "$2" | wc -l) || return 1
		o_n=$((o_n + 0))
		test "$o_n" -le "$o_best" || o_best=$o_n
		o_i=$((o_i + 1))
	done
	echo "$o_best"
}

STRATEGIES="none sat cap group suffix path par sat,cap,group,suffix,path"

check_all () {
	n=$(git show "${1#*..}:f" | wc -l | tr -d " ") &&
	for fp in "" --first-parent
	do
		oracle "$fp" "$1" "$n" >expect || return 1
		for s in $STRATEGIES
		do
			"$LINE_DEPTH" $fp --strategy=$s "$1" max:f >actual &&
			test_cmp expect actual || {
				echo "strategy $s $fp $1" >&2
				return 1
			}
		done
	done
}

test_expect_success 'strategies agree with the oracle on linear histories' '
	for seed in 1 2 3 4 5 6
	do
		git init lin$seed &&
		(
			cd lin$seed &&
			git config diff.renames false &&
			random_history $seed 10 16 &&
			check_all c0..c10
		) || return 1
	done
'

test_expect_success 'strategies agree with the oracle across merges' '
	for seed in 1 2 3 4 5 6
	do
		git init mrg$seed &&
		(
			cd mrg$seed &&
			git config diff.renames false &&
			random_history $seed 3 14 &&
			main=$(git symbolic-ref --short HEAD) &&
			git switch -q -c side c1 &&
			random_edits $((seed + 100)) s 3 &&
			git switch -q "$main" &&
			random_edits $((seed + 200)) m 2 &&
			test_tick &&
			git merge -q -X theirs --no-edit side &&
			random_edits $((seed + 300)) t 2 &&
			check_all c0..t2
		) || return 1
	done
'

test_done
