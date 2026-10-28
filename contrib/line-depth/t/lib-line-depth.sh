# Shared helpers for the line-depth family of tests.

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

# Like cf, but as <name> on a given day number, so that ages are exact.
#   cfa <tag> <name> <day> <path> <line>...
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

# expect_is <script> <arguments>: the script's output must equal the
# key/value lines supplied on standard input.
expect_is () {
	cat >expect &&
	"$@" >actual &&
	test_cmp expect actual
}
