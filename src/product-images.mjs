// Product illustration images from verifiable CC0 / public-domain source material.
// These are REPRESENTATIVE SUBJECT IMAGES, not claims about brand, package or seller stock.
// Real store images from listing_images always take priority.
const commons = file => `https://commons.wikimedia.org/wiki/Special:FilePath/${encodeURIComponent(file)}`;
const library={
 maize:commons('Corn kernels in bowl - Massachusetts.jpg'),
 feed:commons('Alimento para gallo.jpg'),
 seed:commons('Sunflower seedlings IMG-7574.jpg'),
 seedlings:commons('Dwarf sunflower seedling.jpg'),
 dolomite:commons('Dolomite (GeoDIL number - 786).jpg'),
 gloves:commons('Pulling Weeds (53212376247).jpg'),
 cord:commons('Rope001 PREVIEW.jpg'),
};
export function illustrativePhoto(product={}){
 const q=String(`${product.name||''} ${product.category||''}`).toLowerCase();
 if(/dolomit|kapur|kalsium/.test(q))return library.dolomite;
 if(/jagung|corn|maize/.test(q))return library.maize;
 if(/pakan|feed|ayam|ternak/.test(q))return library.feed;
 if(/tali|rafia|rope/.test(q))return library.cord;
 if(/sarung|glove/.test(q))return library.gloves;
 if(/polybag|semai|bibit/.test(q))return library.seedlings;
 if(/benih|seed|kangkung/.test(q))return library.seed;
 return null;
}
