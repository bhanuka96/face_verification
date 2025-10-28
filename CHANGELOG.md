## 0.1.1

* **Feature**: Server-side embedding registration support

  * New method `registerFromEmbedding()` - register pre-computed embeddings directly
  * New method `registerFromEmbeddingsBatch()` - batch register multiple embeddings at once
  * Enables server-side embedding generation for performance optimization
  * Validates embedding size (512 dimensions required)
  * Skips duplicates automatically (existing records preserved)
  * Returns detailed results for tracking success/failure per embedding
* **Feature**: Group photo identification - identify ALL users in a single photo

  * New method `identifyAllUsersFromImagePath()` - detects and identifies multiple faces in one image
  * Returns `List<String>` of all matched user IDs (unique, deduplicated)
  * Enables use cases: group attendance, event check-in, family photo tagging
  * Each detected face is compared against all stored embeddings
  * Works with configurable similarity threshold (default: 0.70)
* **Update**: Upgraded tflite_flutter to 0.12.0 for improved compatibility
* **Example**: Updated demo app with "Identify Group Photo" feature

  * New button to test multi-face identification
  * Displays count and list of identified users
  * Uses gallery picker for group photos
* **API**: All existing methods remain backward-compatible
* **Version**: Minor version bump (0.0.7 → 0.1.1) for significant new capabilities

## 0.0.7

* **Feature**: Support multiple faces per user

  * Users can register multiple face images using different `imageId` values
  * Optional `replace` flag allows overwriting an existing `(id, imageId)` entry
  * Verification checks all faces for a given user (`staffId`) or all users
* **Feature**: Per-user face management functions

  * `getFacesForUser(String id)` – List all face records for a user
  * `getFacesCountForUser(String id)` – Count number of face samples for a user
  * `deleteFace(String id, String imageId)` – Remove a specific face sample
  * `deleteRecord(String id)` – Remove all face samples for a user
* **Database**: Migrated schema to composite primary key `(id, imageId)` with `createdAt` timestamp
* **Docs**: Updated README to reflect multi-face support and new management functions
* **Dependencies / Version**: Bumped package version to `0.0.7`

## 0.0.6

* **Feature**: Added new registration status check functions

  * `isFaceRegistered(String id)` - Check if a face is registered by ID
  * `isFaceRegisteredWithImageId(String id, String imageId)` - Check for specific ID + imageId combination
* **Docs**: Enhanced README with comprehensive registration management section

  * Added detailed examples for registration status checks
  * Included use cases for preventing duplicate registrations
  * Updated feature list to highlight registration status capabilities
  * Fixed iOS Podfile configuration syntax error
  * Clarified `imageId` parameter as required (not optional)
  * Added troubleshooting for "ID already exists" error
* **Dependencies**: Updated example app dependencies

  * `image_picker: ^1.2.0` (from ^1.1.2)
  * Updated various transitive dependencies
* **Dependencies**: Updated plugin dependencies

  * `plugin_platform_interface: ^2.1.8` (from ^2.0.2)
  * `path_provider: ^2.1.5` (from ^2.1.4)

## 0.0.5

* Docs: Fixed repository URL in README issues section

## 0.0.4

* Docs: Complete README overhaul with improved user experience

  * Added clear value proposition and use cases upfront
  * Enhanced step-by-step usage guide with practical examples
  * Improved code snippets with real-world scenarios
  * Added comprehensive troubleshooting section
  * Better organized platform setup instructions
  * Added tips for optimal photo quality and threshold tuning
  * Improved formatting with emojis and visual hierarchy for better readability

## 0.0.3

* Docs: sync install snippet to ^0.0.2
* Metadata refresh to surface repository links on pub.dev

## 0.0.2

* Docs: revamped README (requirements, quick start, staffId behavior)
* Metadata: added homepage/repository/issue_tracker
* License: switched to MIT text

## 0.0.1

* Initial release with on-device face registration/verification, bundled model, and local storage