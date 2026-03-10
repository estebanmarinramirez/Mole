package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	jsonMode := flag.Bool("json", false, "Output snapshot as JSON")
	startTab := flag.Int("tab", 1, "Initial tab (1-5)")
	flag.Parse()

	if *jsonMode {
		runJSON()
	} else {
		runTUI(*startTab - 1) // Convert to 0-indexed.
	}
}

func runJSON() {
	c := NewCollector()
	// First collect initializes.
	c.Collect()
	time.Sleep(2 * time.Second)
	snap := c.Collect()

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(snap); err != nil {
		fmt.Fprintf(os.Stderr, "JSON error: %v\n", err)
		os.Exit(1)
	}
}

func runTUI(tab int) {
	p := tea.NewProgram(newModel(tab), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "network dashboard error: %v\n", err)
		os.Exit(1)
	}
}
