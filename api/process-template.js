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
    // Verify JWT token
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing or invalid authorization header' });
    }

    const token = authHeader.substring(7);
    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'dev-secret-change-me');

    // Check token has template processing scope
    if (!decoded.scope || !decoded.scope.includes('templates.process')) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }

    // Get request data
    const { templateId, templateName, transcript, prompt } = req.body;

    if (!templateId || !transcript || !prompt) {
      return res.status(400).json({ 
        error: 'Missing required fields',
        required: ['templateId', 'transcript', 'prompt']
      });
    }

    // Process the template - check if it references the transcript
    let processedPrompt = prompt;
    
    // If the prompt mentions "this transcript" but doesn't have the actual transcript,
    // append it at the end
    if (prompt.toLowerCase().includes('transcript') && !prompt.includes(transcript)) {
      processedPrompt = `${prompt}\n\nTranscript:\n${transcript}`;
    } else {
      // Otherwise, replace {TRANSCRIPT} placeholder if it exists
      processedPrompt = prompt.replace('{TRANSCRIPT}', transcript);
    }

    // Call OpenAI API
    const openAIResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: 'You are a helpful assistant that processes voice note transcripts according to templates.'
          },
          {
            role: 'user',
            content: processedPrompt
          }
        ],
        temperature: 0.7,
        max_tokens: 1000
      })
    });

    if (!openAIResponse.ok) {
      const error = await openAIResponse.text();
      console.error('OpenAI API error:', error);
      throw new Error('Failed to process template');
    }

    const openAIData = await openAIResponse.json();
    const processedText = openAIData.choices[0].message.content;

    // Return response
    res.status(200).json({
      templateId,
      templateName,
      processedText,
      usage: {
        promptTokens: openAIData.usage?.prompt_tokens || 0,
        completionTokens: openAIData.usage?.completion_tokens || 0,
        totalTokens: openAIData.usage?.total_tokens || 0
      },
      model: openAIData.model
    });

  } catch (error) {
    console.error('Template processing error:', error);
    
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ error: 'Invalid token' });
    }
    
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expired' });
    }
    
    res.status(500).json({ 
      error: 'Failed to process template',
      message: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
};