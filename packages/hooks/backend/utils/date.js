function getFutureUnixTimestamp(days) {
  const now = new Date();
  now.setDate(now.getDate() + days);
  return Math.floor(now.getTime() / 1000);
}

module.exports = {
  getFutureUnixTimestamp
}