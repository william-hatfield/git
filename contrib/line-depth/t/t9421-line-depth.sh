#!/bin/sh

test_description='line-depth: maximum per-line commit depth in a revision range

For each line of <file> in the tip of <X..Y> within <start>,<end>, count the
distinct commits in X..Y that touch it (as "git log -L" tracks it), and print
the largest count.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
LINE_DEPTH="$CURR_DIR"/../line-depth

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

# Write the given lines to <path>, commit them, and tag the commit.
#   cf <tag> <path> <line>...
cf () {
	tag=$1 path=$2 &&
	shift 2 &&
	printf "%s\n" "$@" >"$path" &&
	git add "$path" &&
	test_tick &&
	git commit -q -m "$tag" &&
	git tag "$tag"
}

# depth_is <expected> <line-depth arguments>
depth_is () {
	echo "$1" >expect &&
	shift &&
	"$LINE_DEPTH" "$@" >actual &&
	test_cmp expect actual
}

test_expect_success 'depth of a single line counts distinct commits' '
	git init single &&
	(
		cd single &&
		cf X f anchor &&
		cf A f anchor new &&
		cf B f anchor new-v2 &&
		cf Uo other u &&
		cf C f anchor new-v3 &&
		depth_is 1 X..A 2,2:f &&
		depth_is 2 X..B 2,2:f &&
		depth_is 2 A..C 2:f &&
		depth_is 3 X..C 2,2:f
	)
'

test_expect_success 'a line no commit in the range touches has depth 0' '
	git init untouched &&
	(
		cd untouched &&
		cf X f alpha beta &&
		cf Y f alpha beta-y &&
		depth_is 0 X..Y 1,1:f
	)
'

test_expect_success 'a range is the maximum per-line depth, not the union' '
	git init maximum &&
	(
		cd maximum &&
		cf X f left sep right &&
		cf A f left-a sep right &&
		cf B f left-a sep right-b &&
		depth_is 1 X..B 1,3:f &&
		cf C f left-c sep right-c &&
		depth_is 2 X..C 1,3:f
	)
'

test_expect_success 'a git failure is an error, never a count of zero' '
	git init failure &&
	(
		cd failure &&
		cf X f one &&
		cf Y f two &&
		! "$LINE_DEPTH" X..Y 1,1:missing >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$LINE_DEPTH" no-such-rev..Y 1,1:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err
	)
'

test_expect_success 'an empty revision set has depth 0 once the request validates' '
	git init empty &&
	(
		cd empty &&
		cf X f a b &&
		cf Y f a b2 &&
		depth_is 0 X..X 1,1:f &&
		depth_is 0 Y..X 2,2:f &&
		! "$LINE_DEPTH" X..X 1,1:missing >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$LINE_DEPTH" X..X 3,3:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$LINE_DEPTH" no-such..no-such 1,1:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err
	)
'

test_expect_success 'max:<file> is the maximum depth over every line of the file' '
	git init whole &&
	(
		cd whole &&
		cf X f left sep right &&
		cf A f left-a sep right &&
		cf B f left-a sep right-b &&
		depth_is 1 X..B max:f &&
		cf C f left-c sep right-c &&
		depth_is 2 X..C max:f &&
		depth_is 0 C..C max:f
	)
'

test_expect_success 'max:<file> counts a line without a trailing newline' '
	git init noeol &&
	(
		cd noeol &&
		printf "a\nb" >f &&
		git add f &&
		test_tick &&
		git commit -q -m X &&
		git tag X &&
		printf "a\nb2" >f &&
		git commit -q -a -m A &&
		git tag A &&
		printf "a\nb3" >f &&
		git commit -q -a -m B &&
		git tag B &&
		depth_is 2 X..B max:f &&
		depth_is 2 X..B 2,2:f
	)
'

test_expect_success 'an existing empty file has maximum 0, an explicit range on it is an error' '
	git init emptyfile &&
	(
		cd emptyfile &&
		cf X f a &&
		: >f &&
		git commit -q -a -m Y &&
		git tag Y &&
		depth_is 0 X..Y max:f &&
		! "$LINE_DEPTH" X..Y 1,1:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err
	)
'

test_expect_success 'a file missing at the tip is an error, not an empty file' '
	git init gone &&
	(
		cd gone &&
		cf X f a &&
		git rm -q f &&
		test_tick &&
		git commit -q -m Y &&
		git tag Y &&
		! "$LINE_DEPTH" X..Y max:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err
	)
'

test_expect_success 'a line outside the file is an error, as for git log -L' '
	git init bounds &&
	(
		cd bounds &&
		cf X f l1 l2 l3 &&
		cf A f l1 l2a l3 &&
		! "$LINE_DEPTH" X..A 4,4:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$LINE_DEPTH" X..A 0,2:f >out 2>err &&
		test_must_be_empty out
	)
'

test_expect_success 'a binary file has no lines to measure' '
	git init binary &&
	(
		cd binary &&
		cf X f one &&
		printf "a\0b\n" >bin &&
		git add bin &&
		test_tick &&
		git commit -q -m Y &&
		git tag Y &&
		! "$LINE_DEPTH" X..Y max:bin >out 2>err &&
		test_must_be_empty out &&
		test_grep -i binary err
	)
'

test_expect_success 'paths are relative to the working directory' '
	git init subdir &&
	(
		cd subdir &&
		mkdir sub &&
		cf X sub/f a b &&
		cf A sub/f a b2 &&
		cd sub &&
		depth_is 1 X..A 2,2:f &&
		depth_is 1 X..A max:f
	)
'

test_expect_success 'the base tip as left boundary ignores merged-in upstream work' '
	git init boundary &&
	(
		cd boundary &&
		cf R f v0 sep s0 &&
		cf U f v1 sep s0 &&
		git switch -q -c topic R &&
		cf S1 f v0 sep s1 &&
		test_tick &&
		git merge -q --no-edit U &&
		cf T f v2 sep s1 &&
		depth_is 1 U..T 1,1:f &&
		depth_is 2 R..T 1,1:f
	)
'

test_expect_success 'a reverted change still counts for the line that survives' '
	git init reverted &&
	(
		cd reverted &&
		cf X f old x0 &&
		git switch -q -c side &&
		cf C f new x0 &&
		git switch -q - &&
		cf D other o1 &&
		test_tick &&
		git merge -q --no-edit side &&
		test_tick &&
		git revert --no-edit C >/dev/null &&
		cf E f old x1 &&
		depth_is 2 X..E 1,1:f &&
		depth_is 1 X..E 2,2:f &&
		depth_is 2 X..E max:f
	)
'

test_expect_success 'rename following inherits the diff.renames configuration' '
	git init renames &&
	(
		cd renames &&
		cf R0 old one &&
		cf E1 old two &&
		cf E2 old three &&
		git mv old new &&
		test_tick &&
		git commit -q -m Rn &&
		git tag Rn &&
		depth_is 2 R0..Rn max:new &&
		git config diff.renames false &&
		depth_is 1 R0..Rn max:new
	)
'

test_expect_success '--fast measures only lines added or modified between X and Y' '
	git init fast &&
	(
		cd fast &&
		cf X f left sep right &&
		cf A f left-a sep right &&
		cf B f left-a sep right-b &&
		cf C f left-c sep right-c &&
		depth_is 2 X..C max:f &&
		depth_is 2 --fast X..C max:f &&
		depth_is 2 --fast X..C 1,3:f &&
		depth_is 0 --fast X..C 2,2:f &&
		depth_is 1 --fast X..B 3,3:f &&
		depth_is 0 --fast X..X max:f
	)
'

test_expect_success '--fast skips a line changed and then restored' '
	git init fastrevert &&
	(
		cd fastrevert &&
		cf X f old x0 &&
		cf C f new x0 &&
		cf R f old x0 &&
		cf E f old x1 &&
		depth_is 2 X..E 1,1:f &&
		depth_is 2 X..E max:f &&
		depth_is 0 --fast X..E 1,1:f &&
		depth_is 1 --fast X..E max:f
	)
'

test_expect_success '--fast handles deletions and files created in the range' '
	git init fastmore &&
	(
		cd fastmore &&
		cf X f keep gone keep2 &&
		cf A f keep keep2 &&
		cf B g n1 n2 &&
		cf C g n1 n2b &&
		depth_is 0 --fast X..A max:f &&
		depth_is 2 --fast X..C max:g &&
		depth_is 1 --fast X..C 1,1:g
	)
'

test_expect_success '--fast still validates the request' '
	git init fastbad &&
	(
		cd fastbad &&
		cf X f a b &&
		cf A f a b2 &&
		! "$LINE_DEPTH" --fast X..A 5,5:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$LINE_DEPTH" --fast X..A max:missing >out 2>err &&
		test_must_be_empty out &&
		! "$LINE_DEPTH" --fast no-such..A max:f >out 2>err &&
		test_must_be_empty out
	)
'

test_expect_success '--fast needs an X..Y range' '
	git init fastrange &&
	(
		cd fastrange &&
		cf X f a &&
		cf A f a2 &&
		! "$LINE_DEPTH" --fast A max:f >out 2>err &&
		test_must_be_empty out &&
		test_grep "X\.\.Y" err &&
		! "$LINE_DEPTH" --fast X...A max:f >out 2>err &&
		test_must_be_empty out &&
		test_grep "X\.\.Y" err
	)
'

test_expect_success 'reversed endpoints are swapped and an end past EOF is clamped, as for git log -L' '
	git init clamp &&
	(
		cd clamp &&
		cf X f l1 l2 l3 l4 &&
		cf A f l1 l2a l3 l4 &&
		cf B f l1 l2b l3 l4b &&
		depth_is 2 X..B 4,2:f &&
		depth_is 2 X..B 1,99:f &&
		depth_is 1 X..B 3,99:f &&
		depth_is 0 X..B 1,1:f &&
		! "$LINE_DEPTH" X..B 5,99:f >out 2>err &&
		test_must_be_empty out
	)
'

# Brute force: one "git log -L" per line, the largest count.  Fails if any
# "git log" does.  The optional arguments are extra "git log" options and a
# file of commits not to count.
#   oracle <range> <start> <end> <file> [<log options> [<ignore file>]]
oracle () {
	o_best=0
	o_i=$2
	while test "$o_i" -le "$3"
	do
		git log -L"$o_i,$o_i:$4" $5 --format=%H --no-patch "$1" >oracle.out || return 1
		if test -n "$6"
		then
			{ grep -v -x -F -f "$6" oracle.out >oracle.kept || test $? = 1; } &&
			mv oracle.kept oracle.out || return 1
		fi
		o_n=$(wc -l <oracle.out)
		o_n=$((o_n + 0))
		test "$o_n" -le "$o_best" || o_best=$o_n
		o_i=$((o_i + 1))
	done
	echo "$o_best"
}

test_expect_success 'agrees with the per-line brute force on a history of varied depths' '
	git init varied &&
	(
		cd varied &&
		for k in 0 1 2 3 4 5 6 7 8
		do
			awk -v k=$k "BEGIN { for (i = 1; i <= 24; i++) {
				v = 0
				for (j = 1; j <= k; j++) if (i % (j + 1) == 0) v++
				print \"l\" i \"-\" v } }" >f &&
			git add f &&
			test_tick &&
			git commit -q -m c$k &&
			git tag c$k || return 1
		done &&
		for r in 1,24 5,9 10,10 3,20 7,8 12,24
		do
			s=${r%,*} e=${r#*,} &&
			oracle c0..c8 $s $e f >expect &&
			"$LINE_DEPTH" c0..c8 $r:f >actual &&
			test_cmp expect actual &&
			"$LINE_DEPTH" --fast c0..c8 $r:f >actual &&
			test_cmp expect actual || return 1
		done &&
		oracle c0..c8 1 24 f >expect &&
		"$LINE_DEPTH" c0..c8 max:f >actual &&
		test_cmp expect actual &&
		"$LINE_DEPTH" --fast c0..c8 max:f >actual &&
		test_cmp expect actual &&
		test "$(cat expect)" -gt 3
	)
'

# Number of "git log" runs a command made, from GIT_TRACE.
#   log_runs <command>...
log_runs () {
	rm -f trace &&
	GIT_TRACE="$PWD/trace" "$@" >out 2>/dev/null &&
	grep -c "built-in: git log" trace
}

test_expect_success 'a large uniform change needs few git log runs' '
	git init few &&
	(
		cd few &&
		cf X f first &&
		{
			echo first &&
			test_seq 199
		} >f &&
		git add f &&
		test_tick &&
		git commit -q -m A &&
		git tag A &&
		depth_is 1 X..A max:f &&
		runs=$(log_runs "$LINE_DEPTH" X..A max:f) &&
		test "$runs" -le 40 &&
		depth_is 1 --fast X..A max:f &&
		runs=$(log_runs "$LINE_DEPTH" --fast X..A max:f) &&
		test "$runs" -le 10 &&
		# nothing in the range touches the file: one run settles it
		depth_is 0 A..A max:f &&
		cf B other o &&
		depth_is 0 A..B max:f &&
		runs=$(log_runs "$LINE_DEPTH" A..B max:f) &&
		test "$runs" -le 1
	)
'

test_expect_success '--fast picks the lines -L picks, whatever the diff configuration' '
	git init slide &&
	(
		cd slide &&
		printf "%s\n" a b "" a "" b a b >f &&
		git add f &&
		test_tick &&
		git commit -q -m X &&
		git tag X &&
		# one inserted duplicate: the new b is line 6 or 7, equally valid
		printf "%s\n" a b "" a "" b b a b >f &&
		git commit -q -a -m A &&
		git tag A &&
		depth_is 1 X..A max:f &&
		depth_is 1 --fast X..A max:f &&
		depth_is 1 --fast X..A 7,7:f &&
		git config diff.algorithm patience &&
		git config diff.indentHeuristic true &&
		git config diff.context 9 &&
		git config color.ui always &&
		git config log.showSignature true &&
		git config format.pretty oneline &&
		depth_is 1 X..A max:f &&
		depth_is 1 --fast X..A max:f
	)
'

test_expect_success '--first-parent counts the merge and follows the mainline only' '
	git init firstparent &&
	(
		cd firstparent &&
		cf X f a &&
		cf P f b &&
		git switch -q -c side X &&
		cf Q f c &&
		blob=$(echo c | git hash-object -w --stdin) &&
		tree=$(printf "100644 blob %s\tf\n" "$blob" | git mktree) &&
		test_tick &&
		M=$(git commit-tree "$tree" -p P -p Q -m M) &&
		git tag M "$M" &&
		# M matches Q, so -L follows Q alone and omits M and P
		depth_is 1 X..M 1,1:f &&
		# on the first-parent chain M differs from P, so M and P count
		depth_is 2 --first-parent X..M 1,1:f &&
		depth_is 2 --first-parent X..M max:f &&
		depth_is 2 --fast --first-parent X..M max:f &&
		depth_is 0 --first-parent M..M max:f
	)
'

test_expect_success '--ignore-revs-file leaves listed commits out of the count' '
	git init ignore &&
	(
		cd ignore &&
		cf X f l1 s1 l2 &&
		cf A f l1 s1 l2a &&
		cf F f l1 s1 l2f &&
		cf B f l1 s1 l2b &&
		depth_is 3 X..B 3,3:f &&
		{
			echo "# a reformat" &&
			echo &&
			echo "$(git rev-parse F) # trailing comment"
		} >ignore-revs &&
		depth_is 2 --ignore-revs-file=ignore-revs X..B 3,3:f &&
		depth_is 2 --ignore-revs-file=ignore-revs X..B max:f &&
		depth_is 2 --first-parent --ignore-revs-file=ignore-revs X..B max:f &&
		# a net-changed line can end up with depth 0, so --fast agrees
		git rev-parse A F B >all-revs &&
		depth_is 0 --fast --ignore-revs-file=all-revs X..B max:f &&
		depth_is 0 --ignore-revs-file=all-revs X..B max:f
	)
'

test_expect_success '--ignore-revs-file rejects an unreadable or malformed file' '
	git init badignore &&
	(
		cd badignore &&
		cf X f a &&
		cf P f b &&
		! "$LINE_DEPTH" --ignore-revs-file=missing X..P max:f >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		git rev-parse --short P >short &&
		! "$LINE_DEPTH" --ignore-revs-file=short X..P max:f >out 2>err &&
		test_must_be_empty out &&
		test_grep "full object" err &&
		! "$LINE_DEPTH" --no-such-option X..P max:f >out 2>err &&
		test_must_be_empty out
	)
'

test_expect_success '--ignore-revs-file copes with a very long list' '
	git init longignore &&
	(
		cd longignore &&
		cf X f l1 s1 l2 &&
		cf A f l1 s1 l2a &&
		cf F f l1 s1 l2f &&
		awk "BEGIN { for (i = 1; i <= 30000; i++) printf \"%040x\\n\", i }" \
			>ignore-revs &&
		git rev-parse F >>ignore-revs &&
		depth_is 1 --ignore-revs-file=ignore-revs X..F 3,3:f &&
		depth_is 1 --ignore-revs-file=ignore-revs X..F max:f &&
		depth_is 2 X..F max:f
	)
'

test_expect_success 'a directory or a submodule is not a file to measure' '
	git init notfile &&
	(
		cd notfile &&
		mkdir d &&
		cf X d/f a &&
		git update-index --add --cacheinfo 160000,$(git rev-parse X),sm &&
		test_tick &&
		git commit -q -m S &&
		cf P d/f b &&
		! "$LINE_DEPTH" X..P max:d >out 2>err &&
		test_must_be_empty out &&
		test_grep "not a file" err &&
		! "$LINE_DEPTH" X..P 1,1:sm >out 2>err &&
		test_must_be_empty out &&
		test_grep "not a file" err &&
		depth_is 1 X..P max:d/f
	)
'

test_expect_success 'exact, fast and first-parent agree with the brute force on random histories' '
	for seed in 1 2 3 4 5 6 7 8
	do
		git init fuzz$seed &&
		(
			cd fuzz$seed &&
			random_history $seed 10 16 &&
			n=$(wc -l <f | tr -d " ") &&
			e=$n &&
			test "$e" -le 9 || e=9 &&
			oracle c0..c10 1 $n f >expect.all &&
			oracle c0..c10 3 $e f >expect.mid &&
			for mode in "" --fast --first-parent
			do
				"$LINE_DEPTH" $mode c0..c10 max:f >actual &&
				test_cmp expect.all actual &&
				"$LINE_DEPTH" $mode c0..c10 3,$e:f >actual &&
				test_cmp expect.mid actual || return 1
			done &&
			# a sub-range is never deeper than the range containing it
			whole=$("$LINE_DEPTH" c0..c10 3,$e:f) &&
			sub=$("$LINE_DEPTH" c0..c10 4,4:f) &&
			test "$sub" -le "$whole" &&
			# and the whole file is at least as deep as any part
			all=$("$LINE_DEPTH" c0..c10 max:f) &&
			test "$whole" -le "$all"
		) || return 1
	done
'

test_expect_success 'exact, fast and first-parent agree with the brute force across merges' '
	for seed in 1 2 3 4 5 6
	do
		git init mfuzz$seed &&
		(
			cd mfuzz$seed &&
			random_history $seed 3 14 &&
			main=$(git symbolic-ref --short HEAD) &&
			git switch -q -c side c1 &&
			random_edits $((seed + 100)) s 3 &&
			git switch -q "$main" &&
			random_edits $((seed + 200)) m 2 &&
			test_tick &&
			git merge -q -X theirs --no-edit side &&
			git tag M &&
			random_edits $((seed + 300)) t 2 &&
			for r in c0..t2 c0..M
			do
				tip=${r#*..} &&
				n=$(git show "$tip:f" | wc -l | tr -d " ") &&
				oracle $r 1 $n f >expect.exact &&
				oracle $r 1 $n f --first-parent >expect.fp &&
				"$LINE_DEPTH" $r max:f >actual &&
				test_cmp expect.exact actual &&
				"$LINE_DEPTH" --fast $r max:f >actual &&
				test_cmp expect.exact actual &&
				"$LINE_DEPTH" --first-parent $r max:f >actual &&
				test_cmp expect.fp actual &&
				"$LINE_DEPTH" --fast --first-parent $r max:f >actual &&
				test_cmp expect.fp actual || return 1
			done
		) || return 1
	done
'

test_expect_success '--ignore-revs-file agrees with the brute force on random histories' '
	for seed in 1 2 3 4 5 6
	do
		git init ifuzz$seed &&
		(
			cd ifuzz$seed &&
			random_history $seed 10 16 &&
			git rev-parse c3 c7 c8 >ignored &&
			n=$(wc -l <f | tr -d " ") &&
			oracle c0..c10 1 $n f >expect.all &&
			oracle c0..c10 1 $n f "" ignored >expect &&
			"$LINE_DEPTH" --ignore-revs-file=ignored c0..c10 max:f >actual &&
			test_cmp expect actual &&
			"$LINE_DEPTH" --fast --ignore-revs-file=ignored c0..c10 max:f >actual &&
			test_cmp expect actual &&
			"$LINE_DEPTH" c0..c10 max:f >actual &&
			test_cmp expect.all actual &&
			test "$(cat expect)" -le "$(cat expect.all)"
		) || return 1
	done
'

test_done
