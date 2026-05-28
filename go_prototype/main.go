package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Styles for the UI
var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#7D56F4")).
			Background(lipgloss.Color("#202020")).
			Padding(0, 1)

	infoStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#555555")).
			Italic(true)

	agentStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#04B575")).
			Bold(true)

	userStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#EE6FF8")).
			Bold(true)
)

// Messages for the state machine
type (
	statusMsg string
	streamMsg string
	doneMsg   struct{}
)

type model struct {
	viewport    viewport.Model
	textInput   textinput.Model
	history     []string
	status      string
	isStreaming bool
	err         error
	responses   chan string
}

func initialModel() model {
	ti := textinput.New()
	ti.Placeholder = "Ask the agent..."
	ti.Focus()
	ti.CharLimit = 156
	ti.Width = 40

	vp := viewport.New(80, 20)
	vp.SetContent("Welcome to Ollama Agent (Go Prototype)\nType a query to see reactive streaming...")

	return model{
		textInput: ti,
		viewport:  vp,
		status:    "READY",
		history:   []string{},
		responses: make(chan string),
	}
}

func (m model) Init() tea.Cmd {
	return textinput.Blink
}

// waitForResponse listens on the channel for new tokens
func waitForResponse(ch chan string) tea.Cmd {
	return func() tea.Msg {
		token, ok := <-ch
		if !ok {
			return doneMsg{}
		}
		return streamMsg(token)
	}
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var (
		tiCmd tea.Cmd
		vpCmd tea.Cmd
	)

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.Type {
		case tea.KeyCtrlC, tea.KeyEsc:
			return m, tea.Quit
		case tea.KeyEnter:
			if m.isStreaming {
				return m, nil
			}
			query := m.textInput.Value()
			if query == "" {
				return m, nil
			}
			m.history = append(m.history, fmt.Sprintf("%s %s", userStyle.Render("YOU ›"), query))
			m.textInput.Reset()
			m.isStreaming = true
			m.status = "THINKING"
			m.viewport.SetContent(strings.Join(m.history, "\n"))
			m.viewport.GotoBottom()
			
			// Start the simulation in a goroutine
			go func() {
				words := strings.Fields("I am processing your request: " + query + ". I can help you with file edits, search, and more. This is a real Go goroutine streaming tokens reactively back to the UI thread!")
				for _, word := range words {
					time.Sleep(150 * time.Millisecond)
					m.responses <- word + " "
				}
				close(m.responses)
			}()

			return m, waitForResponse(m.responses)
		}

	case statusMsg:
		m.status = string(msg)
		return m, nil

	case streamMsg:
		if len(m.history) > 0 && strings.HasPrefix(m.history[len(m.history)-1], agentStyle.Render("AGENT ›")) {
			m.history[len(m.history)-1] += string(msg)
		} else {
			m.history = append(m.history, agentStyle.Render("AGENT › ")+string(msg))
		}
		m.viewport.SetContent(strings.Join(m.history, "\n"))
		m.viewport.GotoBottom()
		// Wait for next token
		return m, waitForResponse(m.responses)

	case doneMsg:
		m.isStreaming = false
		m.status = "READY"
		// Re-create channel for next run
		m.responses = make(chan string)
		return m, nil

	case tea.WindowSizeMsg:
		m.viewport.Width = msg.Width
		m.viewport.Height = msg.Height - 6
		m.textInput.Width = msg.Width - 4
	}

	m.textInput, tiCmd = m.textInput.Update(msg)
	m.viewport, vpCmd = m.viewport.Update(msg)
	return m, tea.Batch(tiCmd, vpCmd)
}

func (m model) View() string {
	return fmt.Sprintf(
		"%s  %s\n\n%s\n\n%s\n%s",
		titleStyle.Render("OLLAMA AGENT (GO)"),
		infoStyle.Render(fmt.Sprintf("Status: %s", m.status)),
		m.viewport.View(),
		m.textInput.View(),
		infoStyle.Render(" (ctrl+c to quit)"),
	)
}

func main() {
	p := tea.NewProgram(initialModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Alas, there's been an error: %v", err)
	}
}
