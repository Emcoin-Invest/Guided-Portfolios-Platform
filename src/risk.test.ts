import { describe,expect,it } from 'vitest';
import { preferenceScore,riskBand,needsConsent } from './risk';

describe('risk engine',()=>{
  it('scores five answers on a 0-100 scale',()=>expect(preferenceScore([1,2,3,4,5])).toBe(60));
  it('maps score to risk bands',()=>{
    expect(riskBand(34)).toBe('Conservative');
    expect(riskBand(35)).toBe('Balanced');
    expect(riskBand(69)).toBe('Balanced');
    expect(riskBand(70)).toBe('Aggressive');
  });
  it('requires consent only when recommended band exceeds approved band',()=>{
    expect(needsConsent('Balanced','Aggressive')).toBe(true);
    expect(needsConsent('Aggressive','Balanced')).toBe(false);
  });
});
