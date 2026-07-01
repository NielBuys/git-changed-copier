# Copy Changed Git Files

A simple Windows GUI tool (built with Lazarus/Free Pascal) that extracts all changed files (e.g. `.sql`) between two Git tags and copies them to a target folder. Ideal for developers needing to export change sets between releases.

---

## ✨ Features

- Compare a Git working directory to a specific tag (`git diff --name-only`)
- Filter files by extension (e.g. `*.sql`; blank, `*` or `*.*` = all files)
- Copy changed files while preserving folder structure
- Prevent overwriting if target folder already exists and contains files
- **Add dependent-module files**: for every changed file under a *main* SQL folder
  (e.g. `SQL\WineMS2`), also include the same-named file from *dependent* folders
  (e.g. `SQL\JuiceMS`, `SQL\OliveMS`, `SQL\FarmMS`). This solves the case where a
  module's own copy of an object was not changed in Git but must still be redeployed
  because its WineMS2 counterpart changed. Matching ignores a leading run-order
  prefix (1–2 digits + `_`, e.g. `1_vwDispatches.sql`) on either side, so
  `0_vwProduct.sql` still matches `vwProduct.sql`. Longer numeric prefixes are kept
  intact, so date-stamped migrations (`20200522_…`) only match identical stamps.
- Export the copied file list to a `.csv`
- Settings are automatically saved to an `.ini` file next to the executable

---

## 🖼️ UI Preview

![App Screenshot](docs/screenshot.png)

---

## 🧰 Requirements

- [Git](https://git-scm.com/) installed and available in system `PATH`
- Windows OS
- Lazarus (Free Pascal) to build from source

---

## 🛠️ Usage

📥 **Download the latest `.exe`** from the [Releases page](https://github.com/NielBuys/git-changed-copier/releases) and run it — no installation required.

1. **From Base Folder Path**: Root of the Git working directory
2. **Filters**: File types to include (e.g. `*.sql`)
3. **From Git Tag**: Older tag to compare from (e.g. `v2.38.0n`)
4. **To Base Folder Path**: Root folder where copied files should be saved
5. **To Git Tag**: Subfolder name (e.g. `v2.39.0n`)
6. **Main SQL Folder (rel.)**: Repo-relative folder holding the primary scripts (e.g. `SQL\WineMS2`)
7. **Dependent SQL Folders (rel., `;` separated)**: One or more repo-relative folders that contain module-specific copies of the same objects (e.g. `SQL\JuiceMS;SQL\OliveMS;SQL\FarmMS`)

Click **"Copy Changed Files"** to extract and copy the Git-changed files.  
Click **"Add Dependent Files"** to also copy the same-named files from the dependent
folders for every changed file under the main folder (appends them to the list).  
Click **"Export Changed Files"** to save the file list to a `.csv`.

---

## 📁 INI File Settings

On form close, the app saves the last-used settings to `ChangedGitFiles.ini` in the executable folder. These are reloaded when the app starts.

---

## 📦 Build From Source

1. Open the project `.lpi` file in [Lazarus](https://www.lazarus-ide.org/)
2. Compile and run

---

## 📄 License

This project is open-source under the MIT License.
