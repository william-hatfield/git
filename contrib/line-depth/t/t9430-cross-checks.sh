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

# The old-side line numbers (in <X>) of the net diff <X> <Y> of "f".
#   old_lines <X> <Y>
old_lines () {
	git diff -U0 --diff-algorithm=myers --no-indent-heuristic "$1" "$2" -- f |
	awk '/^@@ / {
		m = $2
		sub(/^-/, "", m)
		n = split(m, p, ",")
		c = (n > 1) ? p[2] : 1
		for (i = 0; i < c; i++)
			print p[1] + i
	}'
}

# touch-footprint worked out another way: for each old-side line of <X>, the
# most recent commit that touched it is the first one "git log -L" lists.
#   independent_footprint <X> <Y>
independent_footprint () {
	old_lines "$1" "$2" >old.lines &&
	: >origins &&
	while read -r line
	do
		git log -L$line,$line:f -n1 --no-patch --format="%H %ct" "$1" >>origins ||
		return 1
	done <old.lines &&
	count=$(grep -c . origins || true) &&
	if test "$count" = 0
	then
		printf "lines 0\ncommits 0\nauthors 0\noldest_days 0\nmedian_days 0\n"
	else
		base=$(git log -1 --format=%ct "$1") &&
		commits=$(cut -d" " -f1 origins | sort -u | wc -l | tr -d " ") &&
		authors=1 &&
		awk -v base="$base" '{ print int((base - $2) / 86400) }' origins |
			sort -n >ages &&
		oldest=$(tail -n 1 ages) &&
		median=$(sed -n "$(((count + 1) / 2))p" ages) &&
		printf "lines %s\ncommits %s\nauthors %s\noldest_days %s\nmedian_days %s\n" \
			"$count" "$commits" "$authors" "$oldest" "$median"
	fi
}

test_expect_success 'touch-footprint equals an independent -L based count, with exact ages' '
	for seed in 1 2 3 4 5 6
	do
		git init age$seed &&
		(
			cd age$seed &&
			RANDOM_STEP=$((86400 * seed)) &&
			random_history $seed 10 16 &&
			independent_footprint c3 c10 >expect &&
			"$BIN"/touch-footprint c3..c10 >actual &&
			test_cmp expect actual &&
			"$BIN"/touch-footprint --jobs=3 c3..c10 >actual &&
			test_cmp expect actual &&
			# the old lines of a wider range are older and more numerous
			independent_footprint c0 c10 >expect &&
			"$BIN"/touch-footprint c0..c10 >actual &&
			test_cmp expect actual
		) || return 1
	done
'

# <file> of 20 long distinct lines, then a copy with one block moved.
#   block_move <seed>
block_move () {
	awk 'BEGIN { for (i = 1; i <= 20; i++) printf "line number %d is long enough\n", i }' >f &&
	git add f &&
	test_tick &&
	git commit -q -m X &&
	git tag X &&
	awk -v seed="$1" '
		{ line[NR] = $0 }
		END {
			srand(seed)
			k = 1 + int(rand() * 4)
			s = 1 + int(rand() * (NR - k + 1))
			m = NR - k
			p = (s - 1 + 1 + int(rand() * m)) % (m + 1)
			r = 0
			for (i = 1; i <= NR; i++)
				if (i < s || i >= s + k)
					rest[++r] = line[i]
			out = 0
			for (i = 0; i <= m; i++) {
				if (i == p)
					for (j = 0; j < k; j++)
						print line[s + j]
				if (i < m)
					print rest[i + 1]
			}
		}' f >g &&
	mv g f &&
	test_tick &&
	git commit -q -a -m Y &&
	git tag Y
}

test_expect_success 'moved-lines sees a moved block as entirely moved' '
	for seed in 1 2 3 4 5 6 7 8
	do
		git init block$seed &&
		(
			cd block$seed &&
			block_move $seed &&
			"$BIN"/moved-lines X..Y >out &&
			added=$(awk "\$1 == \"added\" { print \$2 }" out) &&
			removed=$(awk "\$1 == \"removed\" { print \$2 }" out) &&
			moved_added=$(awk "\$1 == \"moved_added\" { print \$2 }" out) &&
			moved_removed=$(awk "\$1 == \"moved_removed\" { print \$2 }" out) &&
			test "$added" -ge 1 &&
			test "$added" = "$removed" &&
			test "$added" = "$moved_added" &&
			test "$added" = "$moved_removed"
		) || return 1
	done
'

test_expect_success 'change-spread invariants over files in nested directories' '
	for seed in 1 2 3 4 5
	do
		git init multi$seed &&
		(
			cd multi$seed &&
			mkdir -p a/y b &&
			for file in a/x a/y/z b/w top
			do
				awk "BEGIN { for (i = 1; i <= 10; i++) print \"i\" i }" >$file &&
				git add $file || return 1
			done &&
			test_tick &&
			git commit -q -m c0 &&
			git tag c0 &&
			k=1 &&
			while test $k -le 12
			do
				case $(((seed + k) % 4)) in
				0) RANDOM_FILE=a/x ;;
				1) RANDOM_FILE=a/y/z ;;
				2) RANDOM_FILE=b/w ;;
				*) RANDOM_FILE=top ;;
				esac &&
				random_edit $((seed * 100 + k)) c$k &&
				k=$((k + 1)) || return 1
			done &&
			"$BIN"/change-spread c0..c12 >out &&
			git diff --name-only c0 c12 >names &&
			files=$(wc -l <names | tr -d " ") &&
			dirs=$(awk "{ if (sub(/\\/[^\\/]*\$/, \"\")) print; else print \".\" }" names | sort -u | wc -l | tr -d " ") &&
			subsystems=$(awk "{ i = index(\$0, \"/\"); print (i ? substr(\$0, 1, i - 1) : \".\") }" names | sort -u | wc -l | tr -d " ") &&
			cat >expect <<-EOF &&
			commits 12
			merges 0
			authors 1
			files $files
			dirs $dirs
			subsystems $subsystems
			EOF
			grep -E "^(commits|merges|authors|files|dirs|subsystems) " out >actual &&
			test_cmp expect actual &&
			test "$dirs" -le "$files" &&
			test "$subsystems" -le "$dirs" &&
			entropy=$(awk "\$1 == \"entropy\" { print \$2 }" out) &&
			awk -v h="$entropy" -v f="$files" "BEGIN { exit !(h >= 0 && h <= log(f) / log(2) + 0.005) }"
		) || return 1
	done
'

# A history with a side branch from c1, a diverging mainline, a real merge M
# (conflicts settled with -X theirs) and two later commits t1 t2.
#   merge_history <seed>
merge_history () {
	random_history $1 3 14 &&
	main=$(git symbolic-ref --short HEAD) &&
	git switch -q -c side c1 &&
	random_edits $(($1 + 100)) s 3 &&
	git switch -q "$main" &&
	random_edits $(($1 + 200)) m 2 &&
	test_tick &&
	git merge -q -X theirs --no-edit side &&
	git tag M &&
	random_edits $(($1 + 300)) t 2
}

test_expect_success 'churn-ratio over a merge history counts exactly the non-merge commits' '
	for seed in 1 2 3 4
	do
		git init churnmerge$seed &&
		(
			cd churnmerge$seed &&
			merge_history $seed &&
			gross=0 &&
			for c in $(git rev-list --no-merges c0..t2)
			do
				gross=$((gross + $(numstat_total $c^ $c))) || return 1
			done &&
			net=$(numstat_total c0 t2) &&
			rework=$((gross - net)) &&
			if test $rework -lt 0
			then
				rework=0
			fi &&
			expect_is "$BIN"/churn-ratio c0..t2 <<-EOF &&
			gross $gross
			net $net
			rework $rework
			EOF
			test "$gross" -gt 0
		) || return 1
	done
'

test_expect_success 'merge-effort divergence and file sets equal independent calculations' '
	for seed in 1 2 3 4
	do
		git init effort$seed &&
		(
			cd effort$seed &&
			merge_history $seed &&
			base=$(git merge-base M^1 M^2) &&
			left=M^1 right=M^2 &&
			git diff --name-only $base $left | sort >left.files &&
			git diff --name-only $base $right | sort >right.files &&
			comm -12 left.files right.files >both.files &&
			expect_is "$BIN"/merge-effort $left $right <<-EOF
			merge_bases $(git merge-base --all $left $right | wc -l | tr -d " ")
			left_only $(git rev-list --count $right..$left)
			right_only $(git rev-list --count $left..$right)
			files_left $(wc -l <left.files | tr -d " ")
			files_right $(wc -l <right.files | tr -d " ")
			files_both $(wc -l <both.files | tr -d " ")
			conflicts $(get conflicts "$BIN"/merge-effort $left $right)
			EOF
		) || return 1
	done
'

test_expect_success 'forward-survival and touch-footprint bounds hold across merges' '
	for seed in 1 2 3 4
	do
		git init survmerge$seed &&
		(
			cd survmerge$seed &&
			merge_history $seed &&
			lines=$(get lines "$BIN"/forward-survival c1..t2) &&
			removed=$(get removed "$BIN"/forward-survival c1..t2) &&
			points=$(get removal_points "$BIN"/forward-survival c1..t2) &&
			test "$removed" -le "$lines" &&
			test "$points" -le "$removed" &&
			footprint=$(get lines "$BIN"/touch-footprint c1..t2) &&
			test "$footprint" -ge 1 &&
			commits=$(get commits "$BIN"/touch-footprint c1..t2) &&
			test "$commits" -le "$footprint"
		) || return 1
	done
'

test_done
