#!/bin/bash

# Deploy All Voice Note Backend Endpoints
echo "🚀 Deploying Voice Note Backend Endpoints"
echo "========================================"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo "📁 Working in: $TEMP_DIR"
cd "$TEMP_DIR"

# Create API structure
mkdir -p api/auth
mkdir -p api

# Create bootstrap endpoint
cat > api/auth/bootstrap.js << 'EOF'
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
EOF

# Copy process-template endpoint
cp "/Users/rowanbradley/Documents/Voice Note v2/api/process-template.js" api/

# Create package.json
cat > package.json << 'EOF'
{
  "name": "voicenote-backend",
  "version": "1.0.0",
  "dependencies": {
    "jsonwebtoken": "^9.0.0"
  }
}
EOF

# Create vercel.json
cat > vercel.json << 'EOF'
{
  "functions": {
    "api/**/*.js": {
      "maxDuration": 30
    }
  }
}
EOF

echo ""
echo "📋 Created files:"
ls -la api/
ls -la api/auth/
echo ""

# Link to project
echo "🔗 Linking to Vercel project..."
vercel link --yes --project voicenote-backend-api

# Deploy to production
echo "🚀 Deploying to production..."
vercel --prod --yes

echo ""
echo "✅ Deployment complete!"
echo ""
echo "🧪 Test endpoints:"
echo ""
echo "1. Bootstrap endpoint:"
echo "curl -X POST https://voicenote-backend-api.vercel.app/api/auth/bootstrap \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"deviceId\": \"test\", \"platform\": \"iOS\"}'"
echo ""
echo "2. Process template endpoint:"
echo "curl -X POST https://voicenote-backend-api.vercel.app/api/process-template \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -H 'Authorization: Bearer YOUR_TOKEN' \\"
echo "  -d '{\"templateId\": \"test\", \"templateName\": \"Test\", \"transcript\": \"Hello\", \"prompt\": \"Test prompt\"}'"

# Clean up
cd /
rm -rf "$TEMP_DIR"