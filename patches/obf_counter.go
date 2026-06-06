// SPDX-License-Identifier: MIT
//
// Patch for amneziawg-go: implements the <c> (packet counter) tag.
// See: https://github.com/amnezia-vpn/amneziawg-go/issues/120
//
// Добавь "c": newCounterObf в обfBuilders в device/obf.go

package device

import (
	"encoding/binary"
	"sync/atomic"
)

// counterObf реализует тег <c> — 4-байтовый монотонный счётчик пакетов.
//
// Семантика (по доке amneziawg-go README):
//   "Dumps 4-bytes long amount of packets sent by AWG"
//
// Реализация:
//   • Каждый вызов Obfuscate() инкрементирует счётчик и пишет его в dst[0:4]
//     (little-endian uint32, потокобезопасно через atomic).
//   • Счётчик локален для цепочки (per-obfChain), т.е. считает отправки
//     конкретного I-пакета. Это корректно: каждый хендшейк = +1.
//   • Deobfuscate() просто "съедает" 4 байта со стороны получателя (нет
//     верификации — сервер не знает начальное значение счётчика клиента).
//
// Размер в пакете: всегда 4 байта. DeobfuscatedLen = 0 (данные не из src).
type counterObf struct {
	count atomic.Uint32
}

func newCounterObf(val string) (obf, error) {
	return &counterObf{}, nil
}

// Obfuscate записывает текущее значение счётчика (после инкремента) в dst[0:4].
func (c *counterObf) Obfuscate(dst, src []byte) {
	n := c.count.Add(1)
	binary.LittleEndian.PutUint32(dst[:4], n)
}

// Deobfuscate потребляет 4 байта из src, ничего не пишет в dst.
// Всегда возвращает true — контент не верифицируется.
func (c *counterObf) Deobfuscate(dst, src []byte) bool {
	return len(src) >= 4
}

// ObfuscatedLen всегда 4 байта, независимо от длины источника.
func (c *counterObf) ObfuscatedLen(_ int) int { return 4 }

// DeobfuscatedLen = 0: тег не несёт данных из src (генерируется на месте).
func (c *counterObf) DeobfuscatedLen(_ int) int { return 0 }
