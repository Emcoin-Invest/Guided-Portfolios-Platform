export type RiskBand='Conservative'|'Balanced'|'Aggressive';
export function preferenceScore(a:number[]):number{if(a.length!==5)throw new Error('Five answers are required');return Math.round(a.reduce((s,v)=>s+Math.max(1,Math.min(5,v)),0)/25*100)}
export function riskBand(score:number):RiskBand{return score<35?'Conservative':score<70?'Balanced':'Aggressive'}
export function needsConsent(approved:RiskBand,recommended:RiskBand){const rank={Conservative:1,Balanced:2,Aggressive:3};return rank[recommended]>rank[approved]}
