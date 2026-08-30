import { describe, expect, it } from 'vitest'
import { DEEPSEEK_V4_PRICING_USD, isDeepSeekPeak } from '../src/services/pricing'

describe('DeepSeek V4 official pricing', () => {
  it('uses the official weekday peak windows in Beijing time', () => {
    // Monday, Beijing time.
    expect(isDeepSeekPeak(new Date('2026-08-31T01:00:00Z'))).toBe(true)
    expect(isDeepSeekPeak(new Date('2026-08-31T03:59:59Z'))).toBe(true)
    expect(isDeepSeekPeak(new Date('2026-08-31T04:00:00Z'))).toBe(false)
    expect(isDeepSeekPeak(new Date('2026-08-31T06:00:00Z'))).toBe(true)
    expect(isDeepSeekPeak(new Date('2026-08-31T10:00:00Z'))).toBe(false)
  })

  it('keeps Saturday and Sunday off-peak all day', () => {
    expect(isDeepSeekPeak(new Date('2026-08-30T01:00:00Z'))).toBe(false)
    expect(isDeepSeekPeak(new Date('2026-08-30T06:00:00Z'))).toBe(false)
    expect(isDeepSeekPeak(new Date('2026-09-05T01:00:00Z'))).toBe(false)
    expect(isDeepSeekPeak(new Date('2026-09-05T06:00:00Z'))).toBe(false)
  })

  it('keeps off-peak rates at half of peak rates', () => {
    for (const model of Object.values(DEEPSEEK_V4_PRICING_USD)) {
      expect(model.offPeak.cacheHit * 2).toBe(model.peak.cacheHit)
      expect(model.offPeak.cacheMiss * 2).toBe(model.peak.cacheMiss)
      expect(model.offPeak.output * 2).toBe(model.peak.output)
    }
  })
})
