# WordNest artwork

`WordNest.png` is the bundled source artwork for the WordNest application icon, menu-bar icon and first-run mascot. It depicts a custom teal owl with an A/文 translation emblem. The artwork was developed with AI-assisted image editing from an earlier custom owl mascot.

The PNG is checked into the repository. Builds only resize it with macOS `sips` and package the application icon with `iconutil`; building or running WordNest does not call an image-generation service.

## License and attribution

The artwork is **not MIT-licensed**. It is covered by the separate [WordNest Artwork License](LICENSE), with rights reserved by Albort. You may download and fork the repository, build and run WordNest for your own use, and share unmodified official packages under those terms. Independent reuse, artistic adaptations and distribution in modified applications require prior written permission at **albort.yao.xue@gmail.com**. Replace the artwork with your own authorized assets when distributing a modified build. The software code remains under the repository's [MIT License](../../LICENSE).

The artwork's generation history does not establish exclusive intellectual-property rights or trademark clearance. The software license does not grant trademark rights in the WordNest name or logos, or permission to suggest endorsement by the maintainer. Modified distributions should identify their changes clearly and avoid implying they are official WordNest releases.

## Earlier copies

An earlier repository version explicitly included this artwork under MIT. Changing this notice or rewriting Git history does not revoke permissions already granted for earlier copies. Public visibility also permits viewing and forking under GitHub's platform terms; the image is publicly accessible even though its current reuse terms are restricted.

## Building icons

The main build script calls `scripts/build-icons.sh`. To package the artwork separately:

```sh
bash scripts/build-icons.sh /path/to/YourApp.app/Contents/Resources
```

The script creates `WordNest.icns` and `WordNest-menu.png`, and bundles the original as `WordNest-mascot.png` for setup. The build also includes the artwork license as `WordNest-artwork-LICENSE.txt`. Technical resizing is allowed; artistic changes require permission. To redistribute a modified application without that permission, replace `WordNest.png` with your own authorized artwork and update the artwork notices accordingly.
