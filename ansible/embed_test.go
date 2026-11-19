package ansible

import "testing"

func TestFilesEmbedsTasksIncludedByPlaybooks(t *testing.T) {
	if _, err := Files.ReadFile("tasks/rke2-cis-setup.yml"); err != nil {
		t.Fatalf("tasks/ not embedded: %v", err)
	}
}
