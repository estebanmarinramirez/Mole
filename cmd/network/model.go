package main

import (
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

const refreshInterval = 3 * time.Second

type tickMsg struct{}
type metricsMsg struct{ data NetworkSnapshot }

type model struct {
	collector  *Collector
	width      int
	height     int
	snap       NetworkSnapshot
	ready      bool
	collecting bool
	activeTab  int
	filter     string
	filtering  bool
	sortCol    int
}

func newModel(tab int) model {
	if tab < 0 || tab > 4 { tab = 0 }
	return model{collector: NewCollector(), activeTab: tab}
}

func (m model) Init() tea.Cmd {
	return tickAfter(0)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		key := msg.String()

		// Filter input mode.
		if m.filtering {
			switch key {
			case "enter", "esc":
				m.filtering = false
				if key == "esc" { m.filter = "" }
				return m, nil
			case "backspace":
				if len(m.filter) > 0 {
					m.filter = m.filter[:len(m.filter)-1]
				}
				return m, nil
			default:
				if len(key) == 1 {
					m.filter += key
				}
				return m, nil
			}
		}

		switch key {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "1": m.activeTab = 0; return m, nil
		case "2": m.activeTab = 1; return m, nil
		case "3": m.activeTab = 2; return m, nil
		case "4": m.activeTab = 3; return m, nil
		case "5": m.activeTab = 4; return m, nil
		case "tab":
			m.activeTab = (m.activeTab + 1) % 5
			return m, nil
		case "shift+tab":
			m.activeTab = (m.activeTab + 4) % 5
			return m, nil
		case "/":
			if m.activeTab == 2 {
				m.filtering = true
				m.filter = ""
			}
			return m, nil
		case "s":
			if m.activeTab == 2 {
				m.sortCol = (m.sortCol + 1) % 3
			}
			return m, nil
		case "esc":
			m.filter = ""
			return m, nil
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tickMsg:
		if m.collecting { return m, nil }
		m.collecting = true
		return m, m.collectCmd()

	case metricsMsg:
		m.snap = msg.data
		m.collecting = false
		if !m.ready { m.ready = true }
		return m, tickAfter(refreshInterval)
	}

	return m, nil
}

func (m model) View() string {
	if !m.ready {
		return "\n  Loading network data..."
	}

	w := m.width
	if w <= 0 { w = 80 }

	var sections []string

	// Header + tabs
	sections = append(sections, renderHeader(m.snap, w))
	sections = append(sections, renderTabs(m.activeTab, w))
	sections = append(sections, lineStyle.Render(strings.Repeat("╌", min(w, 80))))

	// Tab content
	rxHist, txHist := m.collector.TrafficHistory()
	sigHist, snrHist := m.collector.SignalHistory()

	var content string
	switch m.activeTab {
	case 0: content = renderOverview(m.snap, rxHist, txHist, w)
	case 1: content = renderTraffic(m.snap, rxHist, txHist, w)
	case 2: content = renderConnections(m.snap, m.filter, m.sortCol, w)
	case 3: content = renderDevices(m.snap, w)
	case 4: content = renderWifi(m.snap, sigHist, snrHist, w)
	}
	sections = append(sections, content)

	// Footer
	footer := subtleStyle.Render("  [1-5] tabs  [Tab] next  [q] quit")
	if m.filtering {
		footer = primaryStyle.Render("  Filter: " + m.filter + "_")
	}
	sections = append(sections, footer)

	_ = snrHist // Available for future use.
	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

func (m model) collectCmd() tea.Cmd {
	return func() tea.Msg {
		m.collector.SetActiveTab(m.activeTab)
		data := m.collector.Collect()
		return metricsMsg{data: data}
	}
}

func tickAfter(d time.Duration) tea.Cmd {
	return tea.Tick(d, func(time.Time) tea.Msg { return tickMsg{} })
}
