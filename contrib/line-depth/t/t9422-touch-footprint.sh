#!/bin/sh

test_description='touch-footprint: who last touched the lines a range changes

For the lines of the left side X that the range X..Y modifies or deletes,
report how many lines, prior commits and authors are involved and how old
the lines were at X.  Added lines have no history and are not counted.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
FOOTPRINT="$CURR_DIR"/../touch-footprint

. "$TEST_DIRECTORY"/test-lib.sh

# Commit <path> with the given lines as <name> on a given day number, so that
# ages are exact.   cfa <tag> <name> <day> <path> <line>...
cfa () {
	tag=$1 name=$2 day=$3 path=$4 &&
	shift 4 &&
	printf "%s\n" "$@" >"$path" &&
	git add "$path" &&
	GIT_AUTHOR_NAME=$name GIT_AUTHOR_EMAIL=$name@example.com \
	GIT_AUTHOR_DATE="$(((day + 10000) * 86400)) +0000" \
	GIT_COMMITTER_NAME=$name GIT_COMMITTER_EMAIL=$name@example.com \
	GIT_COMMITTER_DATE="$(((day + 10000) * 86400)) +0000" \
	git commit -q -m "$tag" &&
	git tag "$tag"
}

# footprint_is <lines> <commits> <authors> <oldest> <median> <arguments>
footprint_is () {
	cat >expect <<-EOF &&
	lines $1
	commits $2
	authors $3
	oldest_days $4
	median_days $5
	EOF
	shift 5 &&
	"$FOOTPRINT" "$@" >actual &&
	test_cmp expect actual
}

test_expect_success 'a modified line is attributed to the commit that last touched it' '
	git init modified &&
	(
		cd modified &&
		cfa R alice 100 f l1 l2 l3 l4 l5 &&
		cfa C bob 110 f l1 l2 l3x l4 l5 &&
		cfa X carol 120 f l1 l2 l3x l4 l5x &&
		cfa P dave 125 f l1 l2 l3y l4 l5x &&
		footprint_is 1 1 1 10 10 X..P
	)
'

test_expect_success 'modified and deleted lines from several commits and authors' '
	git init several &&
	(
		cd several &&
		cfa R alice 100 f l1 l2 l3 l4 &&
		cfa B bob 110 f l1 l2b l3 l4 &&
		cfa X carol 120 other o &&
		# delete l1 and l2b, modify l4
		cfa P dave 130 f l3 l4x &&
		footprint_is 3 2 2 20 20 X..P
	)
'

test_expect_success 'added lines and untouched files have no footprint' '
	git init added &&
	(
		cd added &&
		cfa R alice 100 f l1 l2 &&
		cfa X bob 110 other o &&
		cfa P carol 120 f l1 l2 l3 &&
		footprint_is 0 0 0 0 0 X..P &&
		footprint_is 0 0 0 0 0 X..X
	)
'

test_expect_success 'a deleted file counts all its lines' '
	git init deleted &&
	(
		cd deleted &&
		cfa R alice 100 f l1 l2 l3 &&
		cfa X bob 110 other o &&
		git rm -q f &&
		GIT_COMMITTER_DATE="$(((120 + 10000) * 86400)) +0000" git commit -q -m P &&
		git tag P &&
		footprint_is 3 1 1 10 10 X..P
	)
'

test_expect_success 'a pure rename has no footprint, an edit while renaming counts that line' '
	git init renames &&
	(
		cd renames &&
		cfa R alice 100 old l1 l2 l3 &&
		cfa X bob 110 other o &&
		git mv old new &&
		GIT_COMMITTER_DATE="$(((120 + 10000) * 86400)) +0000" git commit -q -m P1 &&
		git tag P1 &&
		footprint_is 0 0 0 0 0 X..P1 &&
		printf "%s\n" l1 l2x l3 >new &&
		GIT_COMMITTER_DATE="$(((130 + 10000) * 86400)) +0000" git commit -q -a -m P2 &&
		git tag P2 &&
		footprint_is 1 1 1 10 10 X..P2
	)
'

test_expect_success 'a change reverted inside the range leaves no net footprint' '
	git init reverted &&
	(
		cd reverted &&
		cfa R alice 100 f l1 l2 &&
		cfa X bob 110 other o &&
		cfa A carol 120 f l1 l2x &&
		cfa B dave 130 f l1 l2 &&
		footprint_is 0 0 0 0 0 X..B
	)
'

test_expect_success 'paths limit the files considered' '
	git init paths &&
	(
		cd paths &&
		cfa R alice 100 f l1 l2 &&
		cfa R2 bob 105 g g1 g2 &&
		cfa X carol 110 other o &&
		printf "%s\n" l1x l2 >f &&
		printf "%s\n" g1 g2x >g &&
		git add f g &&
		GIT_COMMITTER_DATE="$(((120 + 10000) * 86400)) +0000" git commit -q -m P &&
		git tag P &&
		footprint_is 2 2 2 10 5 X..P &&
		footprint_is 1 1 1 5 5 X..P g &&
		footprint_is 1 1 1 10 10 X..P f
	)
'

test_expect_success 'the result does not depend on diff or blame display configuration' '
	git init config &&
	(
		cd config &&
		cfa R alice 100 f a b "" a "" b b a b &&
		cfa X bob 110 other o &&
		cfa P carol 120 f a b "" a "" b a b &&
		"$FOOTPRINT" X..P >expect &&
		git config diff.algorithm patience &&
		git config diff.indentHeuristic true &&
		git config color.ui always &&
		git config diff.context 9 &&
		"$FOOTPRINT" X..P >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'bad input is an error with nothing on stdout' '
	git init errors &&
	(
		cd errors &&
		cfa X alice 100 f l1 &&
		cfa P bob 110 f l1x &&
		! "$FOOTPRINT" >out 2>err &&
		test_must_be_empty out &&
		! "$FOOTPRINT" no-such..P >out 2>err &&
		test_must_be_empty out &&
		test_file_not_empty err &&
		! "$FOOTPRINT" P >out 2>err &&
		test_must_be_empty out &&
		test_grep "X\.\.Y" err &&
		! "$FOOTPRINT" X...P >out 2>err &&
		test_must_be_empty out &&
		test_grep "X\.\.Y" err
	)
'

test_expect_success 'a changed submodule entry is not blamed' '
	git init submodule &&
	(
		cd submodule &&
		cfa R alice 100 f l1 l2 &&
		git update-index --add --cacheinfo 160000,$(git rev-parse R),sm &&
		GIT_COMMITTER_DATE="$(((120 + 10000) * 86400)) +0000" git commit -q -m X &&
		git tag X &&
		git update-index --cacheinfo 160000,$(git rev-parse X),sm &&
		printf "%s\n" l1y l2 >f &&
		git add f &&
		GIT_COMMITTER_DATE="$(((130 + 10000) * 86400)) +0000" git commit -q -m P &&
		git tag P &&
		footprint_is 1 1 1 20 20 X..P
	)
'

test_expect_success 'works from a subdirectory, with paths relative to it' '
	git init subdir &&
	(
		cd subdir &&
		mkdir sub &&
		cfa R alice 100 sub/f l1 l2 &&
		cfa R2 bob 105 g g1 g2 &&
		cfa X carol 110 other o &&
		printf "%s\n" l1x l2 >sub/f &&
		printf "%s\n" g1 g2x >g &&
		git add sub/f g &&
		GIT_COMMITTER_DATE="$(((120 + 10000) * 86400)) +0000" git commit -q -m P &&
		git tag P &&
		cd sub &&
		footprint_is 2 2 2 10 5 X..P &&
		footprint_is 1 1 1 10 10 X..P f
	)
'

test_expect_success '--jobs gives the same result and leaves no temporary files' '
	git init jobs &&
	(
		cd jobs &&
		mkdir tmp &&
		i=1 &&
		while test $i -le 6
		do
			case $((i % 2)) in
			1) who=alice ;;
			*) who=bob ;;
			esac &&
			cfa R$i $who $((99 + i)) f$i a b &&
			i=$((i + 1)) || return 1
		done &&
		cfa X carol 110 other o &&
		i=1 &&
		while test $i -le 6
		do
			printf "%s\n" a2 b >f$i &&
			git add f$i &&
			i=$((i + 1)) || return 1
		done &&
		GIT_COMMITTER_DATE="$(((120 + 10000) * 86400)) +0000" git commit -q -m P &&
		git tag P &&
		footprint_is 6 6 2 10 7 X..P &&
		footprint_is 6 6 2 10 7 --jobs=4 X..P &&
		TMPDIR="$PWD/tmp" "$FOOTPRINT" --jobs=3 X..P >actual &&
		test_cmp expect actual &&
		test_dir_is_empty tmp &&
		! "$FOOTPRINT" --jobs=0 X..P >out 2>err &&
		test_must_be_empty out &&
		! "$FOOTPRINT" --jobs=many X..P >out 2>err &&
		test_must_be_empty out
	)
'

test_done
