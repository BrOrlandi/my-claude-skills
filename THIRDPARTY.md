# Third-Party Skills

This repository curates third-party Claude Code skills by cloning their repositories into the `thirdparty/` directory. This makes them easy to install alongside our own skills and keeps them updatable via `git pull`.

## How to Add a New Third-Party Skill

1. **Analyze the repository** to understand how it exposes its skill (where `SKILL.md` is located relative to the repo root).

2. **Clone the repository** into `thirdparty/`:

   ```bash
   git clone <repo-url> thirdparty/<skill-name>
   ```

3. **Add an entry to `thirdparty-skills.json`**:

   ```json
   {
     "name": "skill-name",
     "repo": "https://github.com/user/repo.git",
     "path": "thirdparty/skill-name",
     "skill_dir": ".",
     "description": "What the skill does"
   }
   ```

   - `name`: The skill name as it will appear in `~/.claude/skills/`.
   - `repo`: Git clone URL.
   - `path`: Local path relative to this repo root.
   - `skill_dir`: Path to the directory containing `SKILL.md` **relative to the cloned repo root**. Use `"."` if `SKILL.md` is at the repo root. Use a subdirectory like `"skills/my-skill"` if nested.
   - `description`: Brief description of what the skill does.

4. **Run `./install.sh`** to create the symlink.

5. **Update `README.md`** to list the new skill in the Third-Party Skills table.

## Updating Third-Party Skills

Run `./update-thirdparty.sh` to pull the latest changes for all cloned third-party skill repositories.

## Notes

- Third-party repos are full git clones (not submodules), so each can be updated independently.
- The `thirdparty/` directory is gitignored — each user clones their own copies.
- The `thirdparty-skills.json` file is the source of truth for which third-party skills are tracked.
