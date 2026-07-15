package fsutil

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

// WriteToDisk extracts all files from an [fs.FS] into the given destination
// directory, preserving the directory structure. It creates directories as
// needed with mode 0755 and writes files with mode 0644.
func WriteToDisk(fsys fs.FS, destDir string) error {
	return fs.WalkDir(fsys, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return fmt.Errorf("walking %s: %w", path, err)
		}

		target := filepath.Join(destDir, path)

		if d.IsDir() {
			return os.MkdirAll(target, 0755)
		}

		data, err := fs.ReadFile(fsys, path)
		if err != nil {
			return fmt.Errorf("reading embedded file %s: %w", path, err)
		}

		return os.WriteFile(target, data, 0644)
	})
}

// WriteToDiskTemp creates a temporary directory with the given pattern and
// extracts all files from the [fs.FS] into it. The caller is responsible for
// removing the directory when done (typically via defer os.RemoveAll(dir)).
func WriteToDiskTemp(fsys fs.FS, pattern string) (string, error) {
	dir, err := os.MkdirTemp("", pattern)
	if err != nil {
		return "", fmt.Errorf("creating temp directory: %w", err)
	}

	if err := WriteToDisk(fsys, dir); err != nil {
		os.RemoveAll(dir) // clean up on failure
		return "", err
	}

	return dir, nil
}

// WriteSubdirToDisk extracts a subdirectory from an [fs.FS] into the given
// destination directory. This is useful when you only need a specific subset
// of the embedded files.
func WriteSubdirToDisk(fsys fs.FS, subdir string, destDir string) error {
	sub, err := fs.Sub(fsys, subdir)
	if err != nil {
		return fmt.Errorf("accessing subdirectory %s: %w", subdir, err)
	}
	return WriteToDisk(sub, destDir)
}
