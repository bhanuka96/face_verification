## 0.0.6

- **Feature**: Added new registration status check functions
  - `isFaceRegistered(String id)` - Check if a face is registered by ID
  - `isFaceRegisteredWithImageId(String id, String imageId)` - Check for specific ID + imageId combination
- **Docs**: Enhanced README with comprehensive registration management section
  - Added detailed examples for registration status checks
  - Included use cases for preventing duplicate registrations
  - Updated feature list to highlight registration status capabilities
  - Fixed iOS Podfile configuration syntax error
  - Clarified `imageId` parameter as required (not optional)
  - Added troubleshooting for "ID already exists" error
- **Dependencies**: Updated example app dependencies
  - `image_picker: ^1.2.0` (from ^1.1.2)
  - Updated various transitive dependencies
- **Dependencies**: Updated plugin dependencies
  - `plugin_platform_interface: ^2.1.8` (from ^2.0.2) 
  - `path_provider: ^2.1.5` (from ^2.1.4)

## 0.0.5

- Docs: Fixed repository URL in README issues section

## 0.0.4

- Docs: Complete README overhaul with improved user experience
  - Added clear value proposition and use cases upfront
  - Enhanced step-by-step usage guide with practical examples
  - Improved code snippets with real-world scenarios
  - Added comprehensive troubleshooting section
  - Better organized platform setup instructions
  - Added tips for optimal photo quality and threshold tuning
  - Improved formatting with emojis and visual hierarchy for better readability

## 0.0.3

- Docs: sync install snippet to ^0.0.2
- Metadata refresh to surface repository links on pub.dev

## 0.0.2

- Docs: revamped README (requirements, quick start, staffId behavior)
- Metadata: added homepage/repository/issue_tracker
- License: switched to MIT text

## 0.0.1

- Initial release with on-device face registration/verification, bundled model, and local storage