#!/bin/sh

test_description='change-spread: how scattered the change made by X..Y is

Counts what the range touches: files, directories, top-level subsystems and
functions (from hunk headers), the entropy of the lines changed per file, and
the commits, merges and authors involved.
'

CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
TEST_DIRECTORY="$CURR_DIR"/../../../t
SPREAD="$CURR_DIR"/../change-spread

. "$TEST_DIRECTORY"/test-lib.sh
. "$CURR_DIR"/lib-line-depth.sh

# A small C-like file whose hunk header names the function.
#   cfunc <tag> <name> <day> <path> <name> <value>
cfunc () {
	mkdir -p "$(dirname "$4")" &&
	cfa "$1" "$2" "$3" "$4" "int $5()" "{" "return $6;" "}"
}

test_expect_success 'spread over files, directories, subsystems and functions' '
	git init spread &&
	(
		cd spread &&
		cfunc R1 alice 100 a/s/x.c one 1 &&
		cfunc R2 alice 101 a/y.c two 2 &&
		cfunc R3 alice 102 b/z.c three 3 &&
		cfa X alice 103 top.txt t &&
		cfunc P1 bob 110 a/s/x.c one 11 &&
		cfunc P2 carol 111 a/y.c two 22 &&
		cfunc P3 carol 112 b/z.c three 33 &&
		cfa P4 carol 113 top.txt t2 &&
		cfunc P5 bob 114 a/s/x.c one 111 &&
		expect_is "$SPREAD" X..P5 <<-\EOF
		commits 5
		merges 0
		authors 2
		files 4
		dirs 4
		subsystems 3
		functions 3
		entropy 2.00
		EOF
	)
'

test_expect_success 'one file has no entropy, an empty range nothing' '
	git init single &&
	(
		cd single &&
		cfunc X alice 100 f.c one 1 &&
		cfunc P alice 110 f.c one 2 &&
		expect_is "$SPREAD" X..P <<-\EOF &&
		commits 1
		merges 0
		authors 1
		files 1
		dirs 1
		subsystems 1
		functions 1
		entropy 0.00
		EOF
		expect_is "$SPREAD" P..P <<-\EOF
		commits 0
		merges 0
		authors 0
		files 0
		dirs 0
		subsystems 0
		functions 0
		entropy 0.00
		EOF
	)
'

test_expect_success 'unequal changes lower the entropy, and merges are counted' '
	git init uneven &&
	(
		cd uneven &&
		cf X f l1 l2 l3 l4 &&
		cf X2 g g1 &&
		git switch -q -c side X &&
		cf S f m1 m2 m3 l4 &&
		git switch -q - &&
		cf D g g2 &&
		test_tick &&
		git merge -q --no-edit side &&
		git tag M &&
		expect_is "$SPREAD" X2..M <<-\EOF
		commits 3
		merges 1
		authors 1
		files 2
		dirs 1
		subsystems 1
		functions 0
		entropy 0.81
		EOF
	)
'

test_expect_success 'paths limit the files considered' '
	git init paths &&
	(
		cd paths &&
		mkdir a b &&
		cf X a/f a1 &&
		cf P1 a/f a2 &&
		cf P2 b/g g2 &&
		expect_is "$SPREAD" X..P2 a <<-\EOF
		commits 1
		merges 0
		authors 1
		files 1
		dirs 1
		subsystems 1
		functions 0
		entropy 0.00
		EOF
	)
'

test_expect_success 'bad input is an error with nothing on stdout' '
	git init errors &&
	(
		cd errors &&
		cf X f a &&
		cf P f b &&
		! "$SPREAD" >out 2>err &&
		test_must_be_empty out &&
		! "$SPREAD" no-such..P >out 2>err &&
		test_must_be_empty out &&
		! "$SPREAD" P >out 2>err &&
		test_must_be_empty out &&
		test_grep "X\.\.Y" err
	)
'

test_done
