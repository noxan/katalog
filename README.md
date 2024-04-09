# Katalog: Your minimalist ebook manager.

![Screenshot of Katalog 0.5](https://github.com/noxan/katalog/blob/66fd1dba2552816c70f4b6b03332d8cdcb3180b4/assets/katalog-0.5.png?raw=true)

⚠️ This project is in an experimental state and not meant for production use.

## Roadmap

- [x] Ebook library
- [x] Epub file support (read-only)
- [x] View ebook metadata
- [x] Import book into library
- [x] Welcome screen when library is empty
- [ ] Edit ebook metadata
- [ ] Convert epub to mobi
- [ ] Transfer ebook to hardware reader (e.g. Kindle)
- [ ] Caching of ebook library
- [x] Dark mode
- [ ] Ebook reading mode
- [ ] Delete ebook from library
- [ ] Search ebook library
- [ ] Sort ebook library by author and book title
- [ ] Automatic updates

## Known issues

- [ ] Cover image display fails for newly imported books
- [ ] Newly imported books are not sorted and in wrong order

## Release guide

1. Increment version number in `package.json`
2. Increment version number in `src-tauri/tauri.conf.json`
3. Create a new git tag with the version number
4. Commit and push changes
5. Export environment variables for signing the app
   `export TAURI_SIGNING_PRIVATE_KEY="content of the generated key"`
6. Build the app with `pnpm tauri build`
7. Create a new release on GitHub
8. Upload the generated binaries to the release on Github
9. Update the `assets/updater.json` with the new download url and signature
