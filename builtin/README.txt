BUILT-IN FALLBACK ART
=====================

This folder is packed inside DogPet.exe. It is the art the app falls back
to when assets/ is missing, unreadable, or every pack in it is broken, so
that DogPet always has something to show and never starts with no dog.

Unlike assets/, this folder IS imported by Godot, so the files here are
loaded with load() rather than read off the disk at runtime. PetLoader
handles both, and picks by whether the pack's folder starts with res://.

Do not edit these to change the app's look - edit assets/ instead. These
are only the safety net.
