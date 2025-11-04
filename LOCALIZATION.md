# Localization

This package uses Apple's standard localization system with `.strings` files and `NSLocalizedString`.

## Supported Languages

The VM window close confirmation dialog is localized for the following languages:

- **Arabic** (ar)
- **Chinese** (zh-Hans) - Simplified Chinese
- **Chinese** (zh-Hant) - Traditional Chinese
- **Dutch** (nl)
- **English** (en, en-GB) - Base language
- **French** (fr) - European French
- **French** (fr-CA) - Canadian French
- **German** (de)
- **Hindi** (hi)
- **Italian** (it)
- **Japanese** (ja)
- **Korean** (ko)
- **Portuguese** (pt) - European Portuguese
- **Portuguese** (pt-BR) - Brazilian Portuguese
- **Russian** (ru)
- **Spanish** (es) - European Spanish
- **Spanish** (es-419) - Latin American Spanish

## How It Works

The system automatically uses the user's macOS system locale to select the appropriate localization. If the specific locale variant isn't available, macOS falls back to the base language, then to English.

For example:
- User with `es-MX` (Mexican Spanish) → uses `es-419` (Latin American Spanish)
- User with `pt-PT` (Portugal) → uses `pt` (European Portuguese)
- User with `ja` (Japanese) → falls back to `en` (English)

## Localization Files

Each locale has a directory containing `Localizable.strings`:

```
ar.lproj/Localizable.strings
de.lproj/Localizable.strings
en.lproj/Localizable.strings
en-GB.lproj/Localizable.strings
es.lproj/Localizable.strings
es-419.lproj/Localizable.strings
fr.lproj/Localizable.strings
fr-CA.lproj/Localizable.strings
hi.lproj/Localizable.strings
it.lproj/Localizable.strings
ja.lproj/Localizable.strings
ko.lproj/Localizable.strings
nl.lproj/Localizable.strings
pt.lproj/Localizable.strings
pt-BR.lproj/Localizable.strings
ru.lproj/Localizable.strings
zh-Hans.lproj/Localizable.strings
zh-Hant.lproj/Localizable.strings
```

## String Keys

The following keys are defined:

- `STOP_VM_TITLE` - Title for the stop VM confirmation dialog
- `STOP_VM_MESSAGE` - Warning message about stopping the VM
- `STOP_VM_STOP` - "Stop" button text
- `STOP_VM_CANCEL` - "Cancel" button text

## Adding New Languages

To add a new language:

1. Create a new directory: `<language-code>.lproj/`
2. Copy `en.lproj/Localizable.strings` to the new directory
3. Translate the strings in the new file
4. Build and test with that system locale

Example for Japanese:
```bash
mkdir ja.lproj
cp en.lproj/Localizable.strings ja.lproj/
# Edit ja.lproj/Localizable.strings and translate
```

## Testing Localizations

To test a specific locale, run your application with the locale environment variable:

```bash
export LANG=pt_BR.UTF-8
./your-app
```

Or use the `-AppleLanguages` argument:

```bash
./your-app -AppleLanguages "(pt-BR)"
```

## Implementation Notes

- Uses `NSLocalizedString` macro in Objective-C code
- Follows Apple Human Interface Guidelines for dialog text
- Button order follows macOS conventions (Cancel is default/leftmost)
- Alert style is `NSAlertStyleCritical` for destructive actions
- Fallback to English if translation is missing
