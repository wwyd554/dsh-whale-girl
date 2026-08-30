export type DeepSeekV4Model = 'deepseek-v4-flash' | 'deepseek-v4-pro'
export type PricePeriod = 'peak' | 'offPeak'

export interface TokenRates {
  cacheHit: number
  cacheMiss: number
  output: number
}

/** USD / 1M tokens. Official V4 pricing effective 2026-08-17 00:00 Beijing time. */
export const DEEPSEEK_V4_PRICING_USD: Record<DeepSeekV4Model, Record<PricePeriod, TokenRates>> = {
  'deepseek-v4-flash': {
    offPeak: { cacheHit: 0.007, cacheMiss: 0.22, output: 0.66 },
    peak: { cacheHit: 0.014, cacheMiss: 0.44, output: 1.32 }
  },
  'deepseek-v4-pro': {
    offPeak: { cacheHit: 0.022, cacheMiss: 0.66, output: 1.98 },
    peak: { cacheHit: 0.044, cacheMiss: 1.32, output: 3.96 }
  }
}

/** Peak: Beijing time Mon-Fri 09:00-12:00 and 14:00-18:00. Weekends are off-peak all day. */
export function isDeepSeekPeak(date: Date): boolean {
  const beijing = new Date(date.getTime() + 8 * 60 * 60 * 1000)
  const weekday = beijing.getUTCDay()
  if (weekday === 0 || weekday === 6) return false
  const hour = beijing.getUTCHours()
  return (hour >= 9 && hour < 12) || (hour >= 14 && hour < 18)
}
