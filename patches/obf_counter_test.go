// SPDX-License-Identifier: MIT
//
// Unit-тест для counterObf (<c> tag).
// Запуск: go test ./device/ -run TestCounterObf -v

package device

import (
	"encoding/binary"
	"testing"
)

// TestCounterObfParse проверяет, что <c> парсится без ошибок.
func TestCounterObfParse(t *testing.T) {
	_, err := newObfChain("<c>")
	if err != nil {
		t.Fatalf("newObfChain(<c>) вернул ошибку: %v", err)
	}
}

// TestCounterObfCombo проверяет <c> в составе сложной цепочки.
func TestCounterObfCombo(t *testing.T) {
	_, err := newObfChain("<b 0xdeadbeef><c><r 8>")
	if err != nil {
		t.Fatalf("newObfChain(<b 0xdeadbeef><c><r 8>) вернул ошибку: %v", err)
	}
}

// TestCounterObfMonotonic проверяет, что счётчик растёт при каждом вызове.
func TestCounterObfMonotonic(t *testing.T) {
	chain, err := newObfChain("<c>")
	if err != nil {
		t.Fatalf("parse: %v", err)
	}

	dst := make([]byte, chain.ObfuscatedLen(0)) // = 4

	chain.Obfuscate(dst, nil)
	v1 := binary.LittleEndian.Uint32(dst)

	chain.Obfuscate(dst, nil)
	v2 := binary.LittleEndian.Uint32(dst)

	chain.Obfuscate(dst, nil)
	v3 := binary.LittleEndian.Uint32(dst)

	if v1 != 1 {
		t.Errorf("первый вызов: ожидалось 1, получено %d", v1)
	}
	if v2 != 2 {
		t.Errorf("второй вызов: ожидалось 2, получено %d", v2)
	}
	if v3 != 3 {
		t.Errorf("третий вызов: ожидалось 3, получено %d", v3)
	}
}

// TestCounterObfLengths проверяет ObfuscatedLen и DeobfuscatedLen.
func TestCounterObfLengths(t *testing.T) {
	o, err := newCounterObf("")
	if err != nil {
		t.Fatalf("newCounterObf: %v", err)
	}
	if got := o.ObfuscatedLen(0); got != 4 {
		t.Errorf("ObfuscatedLen(0) = %d, хотим 4", got)
	}
	if got := o.ObfuscatedLen(100); got != 4 {
		t.Errorf("ObfuscatedLen(100) = %d, хотим 4", got)
	}
	if got := o.DeobfuscatedLen(0); got != 0 {
		t.Errorf("DeobfuscatedLen(0) = %d, хотим 0", got)
	}
}

// TestCounterObfDeobfuscate проверяет, что Deobfuscate принимает 4 байта.
func TestCounterObfDeobfuscate(t *testing.T) {
	o, _ := newCounterObf("")
	src := []byte{0x01, 0x00, 0x00, 0x00}
	dst := []byte{}
	if !o.Deobfuscate(dst, src) {
		t.Error("Deobfuscate вернул false для валидных 4 байт")
	}
	// Меньше 4 байт — должен вернуть false
	if o.Deobfuscate(dst, src[:3]) {
		t.Error("Deobfuscate должен вернуть false для < 4 байт")
	}
}

// TestCounterObfRoundTrip проверяет round-trip через obfChain (только <c>).
func TestCounterObfRoundTrip(t *testing.T) {
	chain, _ := newObfChain("<c>")

	// Obfuscate
	obfLen := chain.ObfuscatedLen(0) // 4
	obfBuf := make([]byte, obfLen)
	chain.Obfuscate(obfBuf, nil)

	// Deobfuscate (dst = 0 байт, как предписывает DeobfuscatedLen=0)
	deobfLen := chain.DeobfuscatedLen(obfLen) // 0
	deobfBuf := make([]byte, deobfLen)
	if !chain.Deobfuscate(deobfBuf, obfBuf) {
		t.Error("chain.Deobfuscate вернул false")
	}
}
