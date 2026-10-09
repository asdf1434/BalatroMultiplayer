#!/usr/bin/env bash
#
# test-two-players.sh: open two Balatro windows on this Mac, both running the
# same copy of the mod, so you can play both sides of a multiplayer lobby.
#
# Usage:
#   scripts/test-two-players.sh [options] [code-folder-or-branch]
#
#   (nothing)            Test the repository this script is in.
#   <branch>             Test the git worktree checked out on that branch, for
#                        example "duel-tax-collector". If git does not know the
#                        branch, the script looks for a sibling folder named
#                        BalatroMP-<branch>.
#   <path>               Test the code in that folder.
#
# Options:
#   --attack-rate <n>    Test copy only: set MP.DUEL.attack_shop_rate to <n> in
#                        layers/duel.lua. It is a shop weight next to Jokers (20),
#                        Tarots (4) and Planets (4), which add up to 28, so about
#                        n / (n + 28) of shop slots are Attack cards:
#                          2  (the normal value) about 7%
#                          10 about 26%, good for testing with normal shops
#                          100 about 78%, Jokers become rare
#                        Stops with an error if that line is not in the code.
#   --boost-attacks      Same as --attack-rate 100.
#   --bounty <goal>      Test copy only: every Duel bounty uses this goal, for
#                        example "lucky" or "exact_money". The goal keys are the
#                        `key = "..."` lines in overrides/duel_bounty.lua.
#   --reset-saves        Throw away both test save folders and copy them again
#                        from your real save (see "Save data" below).
#   --no-launch          Do every step except opening the game windows.
#   --dry-run            Only print what would happen. Changes nothing.
#   -h, --help           Show this help.
#
# What it does, in order:
#   1. Copies the code into a separate mods folder,
#      ~/Library/Application Support/Balatro/Mods-test/BalatroMP
#      (skipping .git, reports and .cmux), and links your installed Steamodded
#      into it. Your normal Mods folder is not touched. Every run copies again,
#      so code changes are picked up.
#   2. Backs up your real save files (profile folders 1, 2, 3, settings.jkr
#      and config/) to ~/Library/Application Support/Balatro-test-backups/<time>
#      and keeps only the newest 10 backups.
#   3. Opens two windows. Logs go to Mods-test/logs/window-1.log and -2.log.
#
# Save data:
#   Each test window saves to its own folder,
#   ~/Library/Application Support/Balatro-test-1 and Balatro-test-2, instead of
#   your real ~/Library/Application Support/Balatro. A small Lovely patch that
#   exists only in Mods-test switches the save folder at startup
#   (love.filesystem.setIdentity) when the BALATRO_TEST_SAVE_ID environment
#   variable is set. On the first run (or with --reset-saves) each test folder
#   starts as a copy of your real save, so unlocks and settings carry over.
#   The backup in step 2 is a second safety net in case the patch ever fails.
#   After launch the script checks the logs to confirm each window uses its
#   test folder, and prints a warning if it cannot confirm it.
#
# Run it again after any code change. Close the old windows first.

set -euo pipefail

# --- fixed locations ---------------------------------------------------------
APP_SUPPORT="$HOME/Library/Application Support"
GAME_DIR="$APP_SUPPORT/Steam/steamapps/common/Balatro"
REAL_SAVE="$APP_SUPPORT/Balatro"
REAL_MODS="$REAL_SAVE/Mods"
TEST_MODS="$REAL_SAVE/Mods-test"
LOG_DIR="$TEST_MODS/logs"
BACKUP_ROOT="$APP_SUPPORT/Balatro-test-backups"
KEEP_BACKUPS=10
TEST_SAVE_PREFIX="Balatro-test-" # save folders: Balatro-test-1, Balatro-test-2
SAVE_ITEMS=(1 2 3 settings.jkr config)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- helpers -----------------------------------------------------------------
usage() {
	# Print the comment block at the top of this file, without the "# " prefix.
	sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '$d'
}

die() {
	echo "Error: $*" >&2
	exit 1
}

# In dry-run mode, print the command instead of running it.
run() {
	if [ "$DRY_RUN" = 1 ]; then
		printf '  would run:'
		printf ' %q' "$@"
		printf '\n'
	else
		"$@"
	fi
}

# Map a branch name to the folder of the git worktree that has it checked out.
worktree_for_branch() {
	git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | awk -v want="refs/heads/$1" '
		/^worktree / { path = substr($0, 10) }
		$0 == "branch " want { print path; exit }
	'
}

# --- options -----------------------------------------------------------------
ATTACK_RATE=""
BOUNTY_GOAL=""
RESET_SAVES=0
LAUNCH=1
DRY_RUN=0
TARGET=""

while [ $# -gt 0 ]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--boost-attacks) ATTACK_RATE=100 ;;
	--attack-rate)
		[ $# -ge 2 ] || die "--attack-rate needs a number, for example --attack-rate 10"
		printf '%s' "$2" | grep -Eq '^[0-9]+(\.[0-9]+)?$' ||
			die "--attack-rate needs a number that is 0 or more (got '$2')"
		ATTACK_RATE="$2"
		shift
		;;
	--bounty)
		[ $# -ge 2 ] || die "--bounty needs a goal key, for example --bounty lucky"
		BOUNTY_GOAL="$2"
		shift
		;;
	--reset-saves) RESET_SAVES=1 ;;
	--no-launch) LAUNCH=0 ;;
	--dry-run) DRY_RUN=1 ;;
	-*) die "unknown option '$1'. Run with --help to see the options." ;;
	*)
		[ -z "$TARGET" ] || die "give only one code folder or branch (got '$TARGET' and '$1')."
		TARGET="$1"
		;;
	esac
	shift
done

# --- which code to test ------------------------------------------------------
if [ -z "$TARGET" ]; then
	SOURCE="$REPO_ROOT"
elif [ -d "$TARGET" ]; then
	SOURCE="$(cd "$TARGET" && pwd)"
else
	SOURCE="$(worktree_for_branch "$TARGET")"
	if [ -z "$SOURCE" ]; then
		SOURCE="$(dirname "$REPO_ROOT")/BalatroMP-$TARGET"
	fi
	[ -d "$SOURCE" ] || die "'$TARGET' is not a folder, and no worktree has a branch with that name.
Worktrees git knows about:
$(git -C "$REPO_ROOT" worktree list 2>/dev/null || echo '  (none found)')"
fi

[ -f "$SOURCE/core.lua" ] && [ -f "$SOURCE/Multiplayer.json" ] ||
	die "$SOURCE does not look like the Multiplayer mod (no core.lua or Multiplayer.json)."
[ -f "$GAME_DIR/liblovely.dylib" ] || die "Lovely not found at $GAME_DIR/liblovely.dylib"
[ -d "$REAL_MODS/smods" ] || die "Steamodded not found at $REAL_MODS/smods"

echo "Code to test: $SOURCE"
[ "$DRY_RUN" = 0 ] || echo "Dry run: nothing will be changed."

# --- 1. build the test mods folder -------------------------------------------
echo
echo "1. Copying the code into $TEST_MODS"
run mkdir -p "$TEST_MODS" "$LOG_DIR"
run ln -sfn "$REAL_MODS/smods" "$TEST_MODS/smods"
run rsync -a --delete --exclude /.git --exclude /reports --exclude /.cmux \
	"$SOURCE/" "$TEST_MODS/BalatroMP/"

# Lovely-only mod that moves the save folder. It only exists in Mods-test.
# priority -100 makes it run before Steamodded's own startup code (priority
# -11), which reads the save folder location. If it ever runs later, it also
# points Steamodded's file helper (SMODS.NFS) at the new folder.
SAVE_MOD="$TEST_MODS/test-save-folder"
if [ "$DRY_RUN" = 1 ]; then
	echo "  would write $SAVE_MOD/lovely.toml and save_folder.lua"
else
	mkdir -p "$SAVE_MOD"
	cat >"$SAVE_MOD/lovely.toml" <<'EOF'
# Written by scripts/test-two-players.sh. Test mods folder only.
[manifest]
version = "1.0.0"
dump_lua = true
priority = -100

[[patches]]
[patches.module]
source = "save_folder.lua"
before = "main.lua"
load_now = true
name = "test_two_players.save_folder"
EOF
	cat >"$SAVE_MOD/save_folder.lua" <<'EOF'
-- Written by scripts/test-two-players.sh. Test mods folder only.
-- Moves Balatro's save folder to ~/Library/Application Support/<id>.
local id = os.getenv("BALATRO_TEST_SAVE_ID")
if id and id ~= "" then
	love.filesystem.setIdentity(id)
	if SMODS and SMODS.NFS then
		SMODS.NFS.setWorkingDirectory(love.filesystem.getSaveDirectory())
	end
	print("[test-two-players] save folder: " .. love.filesystem.getSaveDirectory())
end
return {}
EOF
fi

if [ -n "$ATTACK_RATE" ]; then
	DUEL_FILE="$TEST_MODS/BalatroMP/layers/duel.lua"
	PATTERN='^MP\.DUEL\.attack_shop_rate = '
	if [ "$DRY_RUN" = 1 ]; then
		grep -q "$PATTERN" "$SOURCE/layers/duel.lua" 2>/dev/null ||
			die "--attack-rate/--boost-attacks: no line starting with 'MP.DUEL.attack_shop_rate = ' in $SOURCE/layers/duel.lua"
		echo "  would set MP.DUEL.attack_shop_rate = $ATTACK_RATE in the test copy"
	else
		grep -q "$PATTERN" "$DUEL_FILE" 2>/dev/null ||
			die "--attack-rate/--boost-attacks: no line starting with 'MP.DUEL.attack_shop_rate = ' in layers/duel.lua of this code."
		sed -i '' "s/${PATTERN}.*/MP.DUEL.attack_shop_rate = $ATTACK_RATE/" "$DUEL_FILE"
		echo "  Attack shop rate set to $ATTACK_RATE (test copy only)"
	fi
fi

if [ -n "$BOUNTY_GOAL" ]; then
	BOUNTY_SRC="$SOURCE/overrides/duel_bounty.lua"
	BOUNTY_FILE="$TEST_MODS/BalatroMP/overrides/duel_bounty.lua"
	PATTERN='^MP\.BOUNTY\.force_goal = '
	grep -q "key = \"$BOUNTY_GOAL\"" "$BOUNTY_SRC" 2>/dev/null ||
		die "--bounty: no goal with key \"$BOUNTY_GOAL\" in $BOUNTY_SRC"
	if [ "$DRY_RUN" = 1 ]; then
		echo "  would force every bounty to the \"$BOUNTY_GOAL\" goal in the test copy"
	else
		grep -q "$PATTERN" "$BOUNTY_FILE" 2>/dev/null ||
			die "--bounty: no line starting with 'MP.BOUNTY.force_goal = ' in overrides/duel_bounty.lua of this code."
		sed -i '' "s/${PATTERN}.*/MP.BOUNTY.force_goal = \"$BOUNTY_GOAL\"/" "$BOUNTY_FILE"
		echo "  Every bounty forced to \"$BOUNTY_GOAL\" (test copy only)"
	fi
fi

# --- 2. back up the real save and prepare the test save folders --------------
echo
echo "2. Protecting your save data"
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP="$BACKUP_ROOT/$STAMP"
run mkdir -p "$BACKUP"
for item in "${SAVE_ITEMS[@]}"; do
	if [ -e "$REAL_SAVE/$item" ]; then
		run cp -Rp "$REAL_SAVE/$item" "$BACKUP/"
	fi
done
echo "  Backup: $BACKUP"

# Keep only the newest backups. Folder names are timestamps, so they sort by age.
OLD_BACKUPS="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20*' 2>/dev/null |
	sort -r | tail -n +$((KEEP_BACKUPS + 1)))" || true
if [ -n "$OLD_BACKUPS" ]; then
	while IFS= read -r old; do
		run rm -rf "$old"
	done <<<"$OLD_BACKUPS"
fi

for i in 1 2; do
	TEST_SAVE="$APP_SUPPORT/$TEST_SAVE_PREFIX$i"
	if [ "$RESET_SAVES" = 1 ] && [ -d "$TEST_SAVE" ]; then
		run rm -rf "$TEST_SAVE"
	fi
	if [ "$RESET_SAVES" = 1 ] || [ ! -d "$TEST_SAVE" ]; then
		echo "  Window $i save folder: $TEST_SAVE (new copy of your real save)"
		run mkdir -p "$TEST_SAVE"
		for item in "${SAVE_ITEMS[@]}"; do
			if [ -e "$REAL_SAVE/$item" ]; then
				run cp -Rp "$REAL_SAVE/$item" "$TEST_SAVE/"
			fi
		done
	else
		echo "  Window $i save folder: $TEST_SAVE (kept from last time)"
	fi
done

# --- 3. launch ---------------------------------------------------------------
if [ "$LAUNCH" = 0 ] || [ "$DRY_RUN" = 1 ]; then
	echo
	echo "3. Not opening the game (--no-launch or --dry-run)."
else
	echo
	echo "3. Opening two Balatro windows"
	for i in 1 2; do
		LOG="$LOG_DIR/window-$i.log"
		(
			cd "$GAME_DIR"
			BALATRO_TEST_SAVE_ID="$TEST_SAVE_PREFIX$i" \
				DYLD_INSERT_LIBRARIES=liblovely.dylib LOVELY_MOD_DIR="$TEST_MODS" \
				exec ./Balatro.app/Contents/MacOS/love >"$LOG" 2>&1
		) &
		echo "  Window $i log: $LOG"
		sleep 3
	done

	# Confirm each window switched to its own save folder.
	echo "  Checking that each window uses its test save folder..."
	for i in 1 2; do
		LOG="$LOG_DIR/window-$i.log"
		EXPECTED="$APP_SUPPORT/$TEST_SAVE_PREFIX$i"
		found=""
		for _ in $(seq 1 30); do
			found="$(grep -o '\[test-two-players\] save folder: .*' "$LOG" 2>/dev/null | head -n 1 | sed 's/.*save folder: //')" || true
			[ -n "$found" ] && break
			sleep 1
		done
		if [ "$found" = "$EXPECTED" ]; then
			echo "  Window $i: OK, saving to $found"
		else
			echo "  WARNING: window $i did not confirm its test save folder (got: '${found:-nothing}')."
			echo "  It may be writing to your real save. Close both windows and check $LOG."
		fi
	done
fi

echo
echo "To undo any change to your real save, close Balatro and run:"
printf '  rsync -a %q %q\n' "$BACKUP/" "$REAL_SAVE/"
