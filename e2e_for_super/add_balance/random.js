const list = currencies.split(",");
const random = Math.floor(Math.random() * list.length);
output.selectedCurrency = list[random];
