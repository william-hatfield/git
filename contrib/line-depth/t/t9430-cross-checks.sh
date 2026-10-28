#!/bin/sh

test_description='cross-checks between the line-depth family on random histories

Every script is built from different Git commands, so where they should agree,
agreement is evidence that each is right.  Histories come from
random_history: unique new text on every edit, so no line is ambiguous.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
BIN="$CURR_DIR"/..

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

# value of <key> in the key/value output of a command
#   get <key> <command>...
get () {
	key=$1
	shift &&
	"$@" >get.out &&
	awk -v k="$key" '$1 == k { print $2 }' get.out
}

# Sum of lines added and deleted by one numstat.
#   numstat_total <git diff arguments>
numstat_total () {
	git diff --numstat "$@" |
	awk '$1 != "-" { n += $1 + $2 } END { print n + 0 }'
}

test_expect_success 'touch-footprint lines equal forward-survival removed lines' '
	for seed in 1 2 3 4 5 6 7 8
	do
		git init fp$seed &&
		(
			cd fp$seed &&
			random_history $seed 10 16 &&
			footprint=$(get lines "$BIN"/touch-footprint c3..c10) &&
			removed=$(get removed "$BIN"/forward-survival c3..c10) &&
			test "$footprint" = "$removed" &&
			commits=$(get commits "$BIN"/touch-footprint c3..c10) &&
			authors=$(get authors "$BIN"/touch-footprint c3..c10) &&
			oldest=$(get oldest_days "$BIN"/touch-footprint c3..c10) &&
			median=$(get median_days "$BIN"/touch-footprint c3..c10) &&
			test "$authors" -le "$commits" &&
			test "$commits" -le "$footprint" &&
			test "$median" -le "$oldest"
		) || return 1
	done
'

test_expect_success 'churn-ratio agrees with an independent sum, and gross is at least net' '
	for seed in 1 2 3 4 5 6 7 8
	do
		git init churn$seed &&
		(
			cd churn$seed &&
			random_history $seed 10 16 &&
			gross=0 &&
			k=1 &&
			while test $k -le 10
			do
				gross=$((gross + $(numstat_total c$((k - 1)) c$k))) &&
				k=$((k + 1)) || return 1
			done &&
			net=$(numstat_total c0 c10) &&
			expect_is "$BIN"/churn-ratio c0..c10 <<-EOF &&
			gross $gross
			net $net
			rework $((gross - net))
			EOF
			test "$gross" -ge "$net"
		) || return 1
	done
'

test_expect_success 'change-spread of one file over a linear history' '
	for seed in 1 2 3 4
	do
		git init spread$seed &&
		(
			cd spread$seed &&
			random_history $seed 10 16 &&
			"$BIN"/change-spread c0..c10 >out &&
			grep -v "^functions " out >actual &&
			cat >expect <<-\EOF &&
			commits 10
			merges 0
			authors 1
			files 1
			dirs 1
			subsystems 1
			entropy 0.00
			EOF
			test_cmp expect actual &&
			# every random line looks like a function header to the
			# default funcname pattern, so only the bound is checked
			functions=$(get functions "$BIN"/change-spread c0..c10) &&
			test "$functions" -ge 1
		) || return 1
	done
'

test_expect_success 'moved-lines finds no moves in unique text and matches numstat' '
	for seed in 1 2 3 4
	do
		git init moved$seed &&
		(
			cd moved$seed &&
			random_history $seed 10 16 &&
			added=$(git diff --numstat c0 c10 | awk "{ print \$1 }") &&
			removed=$(git diff --numstat c0 c10 | awk "{ print \$2 }") &&
			expect_is "$BIN"/moved-lines c0..c10 <<-EOF
			added $added
			removed $removed
			moved_added 0
			moved_removed 0
			EOF
		) || return 1
	done
'

test_expect_success 'pre-range-depth equals a per-line brute force over the old side' '
	for seed in 1 2 3 4 5 6
	do
		git init pre$seed &&
		(
			cd pre$seed &&
			random_history $seed 10 16 &&
			git diff -U0 --diff-algorithm=myers --no-indent-heuristic \
				c5 c10 -- f >hunks &&
			awk "/^@@ / { m = \$2; sub(/^-/, \"\", m)
				n = split(m, p, \",\"); c = (n > 1) ? p[2] : 1
				for (i = 0; i < c; i++) print p[1] + i }" hunks >oldlines &&
			awk "/^@@ / { m = \$2; sub(/^-/, \"\", m)
				n = split(m, p, \",\"); c = (n > 1) ? p[2] : 1
				if (c > 0) r++ } END { print r + 0 }" hunks >ranges &&
			best=0 &&
			while read line
			do
				d=$(git log -L$line,$line:f --format=%H --no-patch c0..c5 |
					wc -l) &&
				d=$((d + 0)) &&
				if test "$d" -gt "$best"
				then
					best=$d
				fi || return 1
			done <oldlines &&
			expect_is "$BIN"/pre-range-depth c0 c5..c10 <<-EOF
			ranges $(cat ranges)
			depth $best
			EOF
		) || return 1
	done
'

# Replace line <n> of <file> with <text>.
edit_line () {
	awk -v n="$2" -v t="$3" "NR == n { \$0 = t } { print }" "$1" >edit.tmp &&
	mv edit.tmp "$1"
}

test_expect_success 'merge-effort conflicts equal the conflicts of a real merge' '
	for s in 1 2 3 4 5 6 7 8
	do
		git init merge$s &&
		(
			cd merge$s &&
			test_seq 6 >a &&
			test_seq 6 >b &&
			test_seq 6 >c &&
			git add a b c &&
			test_tick &&
			git commit -q -m base &&
			git tag base &&
			git switch -q -c left &&
			edit_line a $((s % 3 + 1)) left$s &&
			edit_line b 1 left$s &&
			if test $((s % 4)) = 0
			then
				edit_line c 4 left$s
			fi &&
			git commit -q -a -m left &&
			git switch -q -c right base &&
			edit_line a $(((s + 1) % 3 + 1)) right$s &&
			if test $((s % 2)) = 1
			then
				edit_line b 1 right$s
			else
				edit_line b 6 right$s
			fi &&
			if test $((s % 4)) = 0
			then
				edit_line c 4 right$s
			fi &&
			git commit -q -a -m right &&
			git switch -q left &&
			if git merge --no-commit --no-ff right >/dev/null 2>&1
			then
				real=0 &&
				git merge --abort 2>/dev/null || git reset -q --hard
			else
				real=$(git ls-files -u | cut -f2 | sort -u | wc -l | tr -d " ") &&
				git merge --abort
			fi &&
			get conflicts "$BIN"/merge-effort left right >seen &&
			echo "$real" >want &&
			test_cmp want seen
		) || return 1
	done
'

test_done
