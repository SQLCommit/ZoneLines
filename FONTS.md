# Label fonts

[Back to ZoneLines](README.md)

ZoneLines uses GdiFonts and the Windows font system. The picker includes common Windows fonts and eligible fonts from the addon's `fonts/` folder.

## Use a bundled or custom font

1. For a custom font, put its `.ttf` or `.otf` file in `/ashita/addons/zonelines/fonts/`.
2. In Windows Explorer, right-click the font and choose **Install**.
3. Fully close and restart FFXI. Reloading the addon alone is not enough.
4. Open `/zl`, then **Labels → Fonts**, and choose the font.

The bundled optional fonts are **Grammara**, **Mystic Gate**, and **Oswald**. ZoneLines does not install them automatically.

## Font missing from the picker?

Check that the font is both installed in Windows and present in the addon's `fonts/` folder, then restart the game. The picker does not list every installed system font.

The common Windows fonts already listed in the picker need no extra files or installation. Adjust bold, outline, and size in the Labels settings.
