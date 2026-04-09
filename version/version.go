/*
Copyright 2026 The Kubernetes Authors All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package version

import (
	"fmt"
	"os"
	"runtime"
	"strconv"

	"github.com/jedib0t/go-pretty/table"
	"github.com/jedib0t/go-pretty/text"
)

// These are set during build time via -ldflags
var (
	Version   = "latest"
	Revision  = "N/A"
	Branch    = "N/A"
	BuildDate = "N/A"
	Community = "k8s.io"
)

// Info holds the version information of the driver
type Info struct {
	Community    string `json:"Community"`
	Version      string `json:"Version"`
	Revision     string `json:"Revision"`
	Branch       string `json:"Branch"`
	BuildDate    string `json:"Build Date"`
	GoVersion    string `json:"Go Version"`
	Compiler     string `json:"Compiler"`
	Platform     string `json:"Platform"`
	RuntimeCores int    `json:"RuntimeCores"`
	TotalMem     int    `json:"TotalMem"`
}

// GetVersion returns the version information of the driver
func GetVersion() Info {
	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)
	return Info{
		Community:    Community,
		Version:      Version,
		Revision:     Revision,
		Branch:       Branch,
		BuildDate:    BuildDate,
		GoVersion:    runtime.Version(),
		Compiler:     runtime.Compiler,
		Platform:     fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH),
		RuntimeCores: runtime.GOMAXPROCS(0),
		TotalMem:     int(memStats.TotalAlloc / 1024),
	}
}

// Print the version information.
func Print() {
	v := GetVersion()
	t := table.NewWriter()
	t.SetOutputMirror(os.Stdout)

	t.AppendHeader(table.Row{
		"Community",
		"Version",
		"Revision",
		"Branch",
		"Build Date",
		"Go Version",
		"Compiler",
		"Platform",
		"Runtime Cores",
		"Total Memory",
	})

	t.AppendRow([]interface{}{
		v.Community,
		v.Version,
		v.Revision,
		v.Branch,
		v.BuildDate,
		v.GoVersion,
		v.Compiler,
		v.Platform,
		strconv.Itoa(v.RuntimeCores) + " cores",
		strconv.Itoa(v.TotalMem) + " KB",
	})

	t.SetStyle(table.StyleDefault)
	t.Style().Format.Header = text.FormatUpper
	t.Style().Color.Header = text.Colors{text.FgHiBlue}
	t.Style().Options.SeparateRows = true

	t.Render()
}

func Term() string {
	return fmt.Sprint(`
╭╮╭━╮╱╱╭╮╱╱╱╱╱╱╱╭━━━╮╭╮╱╱╱╭╮╱╱╱╱╱╱╭━╮╭━╮╱╱╭╮
┃┃┃╭╯╱╱┃┃╱╱╱╱╱╱╱┃╭━╮┣╯╰╮╱╭╯╰╮╱╱╱╱╱┃┃╰╯┃┃╱╭╯╰╮
┃╰╯╯╭╮╭┫╰━┳━━╮╱╱┃╰━━╋╮╭╋━┻╮╭╋━━╮╱╱┃╭╮╭╮┣━┻╮╭╋━┳┳━━┳━━╮
┃╭╮┃┃┃┃┃╭╮┃┃━╋━━╋━━╮┃┃┃┃╭╮┃┃┃┃━╋━━┫┃┃┃┃┃┃━┫┃┃╭╋┫╭━┫━━┫
┃┃┃╰┫╰╯┃╰╯┃┃━╋━━┫╰━╯┃┃╰┫╭╮┃╰┫┃━╋━━┫┃┃┃┃┃┃━┫╰┫┃┃┃╰━╋━━┃
╰╯╰━┻━━┻━━┻━━╯╱╱╰━━━╯╰━┻╯╰┻━┻━━╯╱╱╰╯╰╯╰┻━━┻━┻╯╰┻━━┻━━╯
`)
}
