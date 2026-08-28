function requestTiming(req, res, next) {
  const startNs = process.hrtime.bigint();

  res.on('finish', () => {
    const durationMs = Number(process.hrtime.bigint() - startNs) / 1e6;
    const contentLength = res.getHeader('content-length') || '-';
    console.log(
      `[http] ${req.method} ${req.originalUrl} ${res.statusCode} ${durationMs.toFixed(1)}ms bytes=${contentLength}`
    );
  });

  next();
}

module.exports = requestTiming;
