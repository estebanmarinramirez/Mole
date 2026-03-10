package main

// Top 60 OUI prefixes (normalized to 6 hex chars, uppercase, no separators).
var ouiTable = map[string]string{
	// Apple
	"F4D488": "Apple", "3C22FB": "Apple", "A4B197": "Apple",
	"A860B6": "Apple", "38C986": "Apple", "D0C5F3": "Apple",
	"AC87A3": "Apple", "7CD1C3": "Apple", "F0B479": "Apple",
	"B8E856": "Apple", "6C709F": "Apple", "8C8590": "Apple",
	// Samsung
	"00166C": "Samsung", "8CC8CD": "Samsung", "7811DC": "Samsung",
	"B47443": "Samsung", "A82BB9": "Samsung", "684898": "Samsung",
	// Google / Nest
	"F4F5D8": "Google", "A47733": "Google", "546009": "Google",
	"3C5AB4": "Google",
	// Amazon
	"F0272D": "Amazon", "747548": "Amazon", "6854FD": "Amazon",
	"40B4CD": "Amazon", "FC65DE": "Amazon",
	// AVM Fritz!Box
	"04B4FE": "AVM Fritz", "3C4E47": "AVM Fritz", "2C3AFD": "AVM Fritz",
	"C80E14": "AVM Fritz", "244E7B": "AVM Fritz",
	// Sonos
	"B8E937": "Sonos", "949F3E": "Sonos", "347E5C": "Sonos",
	// TP-Link
	"50C7BF": "TP-Link", "6466B3": "TP-Link", "300D43": "TP-Link",
	// Intel
	"001517": "Intel", "3C970E": "Intel", "8086F2": "Intel",
	// Raspberry Pi
	"B827EB": "Raspberry Pi", "D83ADD": "Raspberry Pi", "E45F01": "Raspberry Pi",
	// Philips Hue
	"001788": "Philips Hue", "ECBA97": "Philips Hue",
	// Microsoft
	"001DD8": "Microsoft", "0050F2": "Microsoft", "7C1E52": "Microsoft",
	// Synology
	"001132": "Synology",
	// Dell
	"F8BC12": "Dell", "00188B": "Dell",
	// HP
	"3C4A92": "HP", "2C768A": "HP",
	// Linksys
	"00259C": "Linksys", "C0563A": "Linksys",
	// Netgear
	"006B9E": "Netgear", "2CB05D": "Netgear",
	// Ubiquiti
	"802AA8": "Ubiquiti", "E063DA": "Ubiquiti",
	// Xiaomi
	"28E31F": "Xiaomi", "64CC2E": "Xiaomi",
	// Espressif (ESP32)
	"240AC4": "Espressif", "3C71BF": "Espressif",
}

// lookupVendor returns the vendor name for a MAC address.
func lookupVendor(mac string) string {
	if mac == "" {
		return ""
	}

	// Normalize: uppercase, remove separators, take first 6 chars.
	var norm []byte
	for _, c := range []byte(mac) {
		if c == ':' || c == '-' || c == '.' {
			continue
		}
		if c >= 'a' && c <= 'f' {
			c -= 'a' - 'A'
		}
		norm = append(norm, c)
	}
	if len(norm) < 6 {
		return ""
	}
	oui := string(norm[:6])

	if v, ok := ouiTable[oui]; ok {
		return v
	}

	// Check locally administered bit (randomized MAC).
	firstByte := hexVal(norm[0])*16 + hexVal(norm[1])
	if firstByte&0x02 != 0 {
		return "Private"
	}
	return ""
}

func hexVal(b byte) byte {
	switch {
	case b >= '0' && b <= '9':
		return b - '0'
	case b >= 'A' && b <= 'F':
		return b - 'A' + 10
	default:
		return 0
	}
}
