const jwt = require('jsonwebtoken');

module.exports = async (req, res) => {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,PATCH,DELETE,POST,PUT');
  res.setHeader('Access-Control-Allow-Headers', 'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version, Authorization');

  // Handle preflight
  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  // Only allow POST
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { deviceId, platform, appVersion, systemVersion } = req.body;

    // Validate required fields
    if (!deviceId || !platform) {
      return res.status(400).json({ 
        error: 'Missing required fields',
        required: ['deviceId', 'platform']
      });
    }

    // Log for debugging (remove in production)
    console.log('Bootstrap token requested:', {
      deviceId,
      platform,
      appVersion,
      systemVersion,
      timestamp: new Date().toISOString()
    });

    // Create JWT payload
    const payload = {
      deviceId,
      platform,
      appVersion: appVersion || '1.0',
      systemVersion: systemVersion || 'unknown',
      scope: ['templates.read', 'templates.process'],
      type: 'bootstrap',
      iat: Math.floor(Date.now() / 1000)
    };

    // Sign token - expires in 1 hour
    const token = jwt.sign(
      payload,
      process.env.JWT_SECRET || 'dev-secret-change-me',
      {
        expiresIn: '1h',
        issuer: 'voicenote-api',
        audience: 'voicenote-app'
      }
    );

    // Return token
    res.status(200).json({
      token,
      expiresIn: 3600, // 1 hour in seconds
      refreshToken: null, // No refresh for bootstrap tokens
      scope: ['templates.read', 'templates.process']
    });

  } catch (error) {
    console.error('Bootstrap error:', error);
    res.status(500).json({ 
      error: 'Failed to generate bootstrap token',
      message: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
};