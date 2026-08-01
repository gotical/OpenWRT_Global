from PIL import Image, ImageDraw

size = 1024
corner = 220
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Градиентный фон (приближенно)
for y in range(size):
    r = int(0 + (0 - 0) * y / size)
    g = int(168 + (210 - 168) * y / size)
    b = int(232 + (184 - 232) * y / size)
    draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

# Закруглённая маска
mask = Image.new('L', (size, size), 0)
mask_draw = ImageDraw.Draw(mask)
mask_draw.rounded_rectangle((0, 0, size, size), radius=corner, fill=255)
img.putalpha(mask)

# Антенки
for x in (250, 774):
    draw.rounded_rectangle((x - 30, 200, x + 30, 420), radius=30, fill=(234, 248, 255, 80))
    draw.ellipse((x - 35, 185, x + 35, 255), fill=(255, 255, 255, 230))

# Корпус роутера
draw.rounded_rectangle((160, 420, 864, 800), radius=120, fill=(255, 255, 255, 255))

# Светодиоды
for x, color in [(315, (0, 198, 255)), (512, (0, 210, 184)), (709, (0, 229, 168))]:
    draw.ellipse((x - 55, 505, x + 55, 615), fill=color + (255,))

# Полоска
draw.rounded_rectangle((280, 680, 744, 716), radius=18, fill=(208, 230, 243, 255))

# Тень
draw.ellipse((420, 180, 604, 250), fill=(255, 255, 255, 90))

img.save('assets/icon/router_icon.png')
print('Saved assets/icon/router_icon.png')
