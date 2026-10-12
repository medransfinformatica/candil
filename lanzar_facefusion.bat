@echo off & title Lanzador FaceFusion & cd /d "%~dp0facefusion" & call venv\Scripts\activate.bat & python facefusion.py run & pause
