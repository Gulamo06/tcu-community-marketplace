# TCU Community Marketplace

A modern, professional web application for university students to buy, sell, donate, and find lost items within the Tzu Chi University community.

## Features

- **Browse Marketplace**: View all active listings with advanced filtering
- **Post Items**: Create listings for sale, donation, lost/found items
- **Category Navigation**: Large, interactive category cards for easy navigation
- **Search & Filter**: Powerful search with category filtering
- **Favorites**: Heart items for later reference
- **Contact System**: Direct messaging and contact options
- **Admin Panel**: Moderation tools for administrators
- **Responsive Design**: Works on desktop and mobile devices

## Recent Updates

### UI/UX Redesign (Latest)
- **Modern Header**: Large title with prominent "Post Item" button
- **Category Cards**: Replaced filter tabs with large, interactive cards
- **Enhanced Search**: Wide search bar with integrated category dropdown
- **Improved Item Cards**: Added favorite buttons, better user info display
- **Better Sidebar**: Organized navigation into Main/User/System sections
- **Interactive Elements**: Hover effects, smooth transitions, visual feedback
- **Professional Design**: Clean, modern styling with consistent spacing

## Tech Stack

- **Frontend**: HTML5, CSS3, JavaScript (ES6+)
- **Styling**: Tailwind CSS with custom CSS
- **Backend**: Supabase (PostgreSQL, Authentication, Storage)
- **Icons**: Custom SVG icons
- **Fonts**: Inter, Noto Sans TC, Playfair Display

## Getting Started

### Prerequisites
- Modern web browser
- Internet connection (for Supabase integration)

### Local Development

1. **Clone/Download** the project files
2. **Start a local server**:
   ```bash
   cd "path/to/project/folder"
   python -m http.server 8000
   ```
3. **Open in browser**: `http://localhost:8000`

### Configuration

The app uses Supabase for backend services. Configuration is in the JavaScript section:

```javascript
const SUPABASE_URL = 'https://wpficqckzvrpfipbpyer.supabase.co';
const SUPABASE_ANON = 'sb_publishable_Lc5H-QXMDPBnb25hrjbm6g_uK3oUrTT';
```

## Key Features Explained

### Navigation Structure
- **Main**: Browse, Marketplace, Lost & Found, Donations
- **User**: My Listings, Messages
- **System**: Settings, Admin (if applicable)

### Item Categories
- **Marketplace**: Buy/sell items with pricing
- **Lost**: Report lost items
- **Found**: Report found items
- **Donations**: Give/receive items for free

### User Experience
- **Guest Mode**: Browse without signing in
- **Student Verification**: Upload ID for posting privileges
- **Contact Options**: Email, WhatsApp, LINE, Instagram
- **7-Day Expiry**: Items auto-expire unless renewed

## Design Principles

- **Professional**: Clean, modern SaaS-style design
- **User-Focused**: Clear hierarchy and intuitive navigation
- **Interactive**: Hover effects and smooth transitions
- **Responsive**: Works on all device sizes
- **Accessible**: Proper contrast, keyboard navigation

## Browser Support

- Chrome 80+
- Firefox 75+
- Safari 13+
- Edge 80+

## Contributing

This is a demonstration project. For production use, consider:
- Environment variables for configuration
- Proper error handling
- Security audits
- Performance optimization

## License

Demo project - use for educational purposes.