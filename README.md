# MoleDesk

MoleDesk is a macOS SwiftUI graphical front end for safely inspecting and managing disk cleanup.

## Target
- macOS Monterey 12 or later
- Intel x86_64
- Traditional Chinese interface

## v0.3 source
This repository has been initialized for MoleDesk v0.3. Add `Package.swift`, `Sources/MoleDesk/main.swift`, `Sources/MoleDesk/Extras.swift` and `LICENSE` from the project source archive before building.

## Safety
The graphical cleanup flow should require scanning, item selection and explicit confirmation. A third-party command-line cleanup operation that permanently deletes files must not be presented as restorable.

## Build
Run **Actions → Build macOS Intel → Run workflow** after uploading the Swift sources. Download the artifact from the completed run. The resulting app is unsigned and unnotarized and should be tested with expendable data first.
