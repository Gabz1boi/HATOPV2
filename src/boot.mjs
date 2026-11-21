if(globalThis.HATOP_CONFIG?.url && globalThis.HATOP_CONFIG?.publishableKey){
  await import('./cloud-app.mjs');
}else{
  await import('./main.mjs');
}
