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

# A deterministic random history of one file "f": commit c0 has <lines> lines
# and each later commit c1..c<n> modifies, inserts or deletes one to three
# of them.  Every new line has text that never occurred before, so a line's
# identity is never ambiguous and nothing is ever restored.
#   random_history <seed> <commits> <lines>
random_history () {
	seed=$1 count=$2 size=$3 &&
	awk -v n="$size" "BEGIN { for (i = 1; i <= n; i++) print \"i\" i }" >f &&
	git add f &&
	test_tick &&
	git commit -q -m c0 &&
	git tag c0 &&
	k=1 &&
	while test "$k" -le "$count"
	do
		awk -v seed=$((seed * 1000 + k)) -v uid="$seed.$k" '
			BEGIN { srand(seed) }
			{ line[NR] = $0 }
			END {
				n = NR
				ops = 1 + int(rand() * 3)
				for (o = 0; o < ops; o++) {
					r = rand()
					i = 1 + int(rand() * n)
					if (r < 0.55) {
						line[i] = "m" uid "." o
					} else if (r < 0.8) {
						for (j = n; j > i; j--)
							line[j + 1] = line[j]
						line[i + 1] = "n" uid "." o
						n++
					} else if (n > 4) {
						for (j = i; j < n; j++)
							line[j] = line[j + 1]
						n--
					}
				}
				for (i = 1; i <= n; i++)
					print line[i]
			}' f >g &&
		mv g f &&
		git commit -q -a -m c$k &&
		git tag c$k &&
		k=$((k + 1)) || return 1
	done
}
