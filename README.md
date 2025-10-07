https://www.marcusfolkesson.se/blog/capture-a-picture-with-v4l2/
https://www.kernel.org/doc/html/latest/userspace-api/media/index.html

Raw images can be converted with ffmpeg  
`ffmpeg -f rawvideo -s <height>x<width> -pix_fmt <pixelformat> -i img.raw out.<preffered extension>`
