const express = require('express');
const guide = require('../guide');

const router = express.Router();

router.get('/guide', async (req, res) => {
  try {
    const channels = await guide.getGuide({ duration: 6 });
    res.render('guide', { channels: channels || [], error: null, now: Math.floor(Date.now() / 1000) });
  } catch (err) {
    res.render('guide', { channels: [], error: err.message, now: Math.floor(Date.now() / 1000) });
  }
});

module.exports = router;
