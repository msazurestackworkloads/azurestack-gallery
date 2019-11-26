package main

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"fmt"
	"io/ioutil"
	"os"
	"strings"
)

func main() {
	scriptstring := getBase64CustomScript(os.Args[1])
	customerString := getSingleLine("scripts/encode/template.yaml", scriptstring)
	fmt.Print(fmt.Sprintf("[base64(concat('%s'))]", customerString))
}

// getBase64CustomScript will return a base64 of the CSE
func getSingleLine(csFilename string, scriptstring string) string {
	b, err := ioutil.ReadFile(csFilename)
	if err != nil {
		// this should never happen and this is a bug
		panic(fmt.Sprintf("BUG: %s", err.Error()))
	}
	// translate the parameters
	csStr := string(b)
	csStr = strings.Replace(csStr, "SCRIPT_PLACEHOLDER", scriptstring, -1)
	csStr = strings.Replace(csStr, "\r\n", "\n", -1)
	return escapeSingleLine(csStr)
}

func escapeSingleLine(escapedStr string) string {
	// template.JSEscapeString leaves undesirable chars that don't work with pretty print
	escapedStr = strings.Replace(escapedStr, "\\", "\\\\", -1)
	escapedStr = strings.Replace(escapedStr, "\r\n", "\\n", -1)
	escapedStr = strings.Replace(escapedStr, "\n", "\\n", -1)
	escapedStr = strings.Replace(escapedStr, "\"", "\\\"", -1)
	return escapedStr
}

// getBase64CustomScript will return a base64 of the CSE
func getBase64CustomScript(csFilename string) string {
	b, err := ioutil.ReadFile(csFilename)
	if err != nil {
		// this should never happen and this is a bug
		panic(fmt.Sprintf("BUG: %s", err.Error()))
	}
	// translate the parameters
	csStr := string(b)
	csStr = strings.Replace(csStr, "\r\n", "\n", -1)
	return getBase64CustomScriptFromStr(csStr)
}

// getBase64CustomScript will return a base64 of the CSE
func getBase64CustomScriptFromStr(str string) string {
	var gzipB bytes.Buffer
	w := gzip.NewWriter(&gzipB)
	w.Write([]byte(str))
	w.Close()
	return base64.StdEncoding.EncodeToString(gzipB.Bytes())
}
