# Scripts

## `test-two-players.sh`: test multiplayer alone on one Mac

Opens two Balatro windows that both run the same copy of the mod. Host a lobby in one window and join it from the other.

macOS only. It expects Balatro from Steam at `~/Library/Application Support/Steam/steamapps/common/Balatro` with Lovely installed (`liblovely.dylib`), and Steamodded at `~/Library/Application Support/Balatro/Mods/smods`.

```bash
scripts/test-two-players.sh                        # test this repository
scripts/test-two-players.sh duel-tax-collector     # test the worktree on that branch
scripts/test-two-players.sh ../some/other/folder   # test any folder
scripts/test-two-players.sh --boost-attacks duel-tax-collector
scripts/test-two-players.sh --dry-run              # print the steps, change nothing
scripts/test-two-players.sh --help                 # all options
```

Run it again after every code change (close the old windows first). It copies the code each time.

### Where things go

| What | Folder |
|---|---|
| Copy of the code under test | `~/Library/Application Support/Balatro/Mods-test/BalatroMP` |
| Window logs | `~/Library/Application Support/Balatro/Mods-test/logs/window-1.log`, `window-2.log` |
| Window 1 and 2 save data | `~/Library/Application Support/Balatro-test-1`, `Balatro-test-2` |
| Backups of your real save | `~/Library/Application Support/Balatro-test-backups/<date_time>` (newest 10 kept) |

Your normal `Mods` folder and your real save in `~/Library/Application Support/Balatro` are not changed.

### How your save data is protected

- Each window saves to its own test folder. The script adds a small Lovely patch to `Mods-test` only. At startup it calls `love.filesystem.setIdentity` with the folder name from the `BALATRO_TEST_SAVE_ID` environment variable. After launch, the script reads the logs and prints `OK` for each window, or a warning if it could not confirm the switch.
- The first time (or with `--reset-saves`), each test folder starts as a copy of your real save, so your unlocks and settings carry over. After that, the test folders keep their own progress.
- Before each launch, the script also backs up your real profile folders (`1`, `2`, `3`), `settings.jkr`, and `config/`. At the end it prints a restore command like this:

  ```bash
  rsync -a "$HOME/Library/Application Support/Balatro-test-backups/<date_time>/" "$HOME/Library/Application Support/Balatro/"
  ```

  Close Balatro before you restore.

### Options

| Option | Effect |
|---|---|
| `--boost-attacks` | Sets `MP.DUEL.attack_shop_rate = 100` in the test copy of `layers/duel.lua`. Stops with an error if that line does not exist. |
| `--reset-saves` | Deletes both test save folders and copies them again from your real save. |
| `--no-launch` | Copies the code and backs up the save, but does not open the game. |
| `--dry-run` | Only prints what would happen. |
