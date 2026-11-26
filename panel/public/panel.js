/* Panel del BIFI · comportamiento visual.
   Solo mejora lo que se ve: tema, números que cuentan, barras que crecen, búsqueda y orden en las tablas.
   Si JavaScript falla, el panel funciona igual (la seguridad y los datos están en el servidor). */
(() => {
  'use strict';
  const $  = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reducir = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const sinAcentos = t => t.toLowerCase().normalize('NFD').replace(/\p{M}/gu, '');
  const matiz = t => { let h = 0; for (const c of t) h = (h * 31 + c.charCodeAt(0)) % 360; return h; };

  /* ---- Tema claro / oscuro (se recuerda en el navegador) ---- */
  const html = document.documentElement, botonTema = $('#tema');
  if (botonTema) {
    botonTema.addEventListener('click', () => {
      const nuevo = html.dataset.tema === 'claro' ? 'oscuro' : 'claro';
      html.dataset.tema = nuevo;
      try { localStorage.setItem('panel-tema', nuevo); } catch (e) {}
    });
  }

  /* ---- Sombra de la barra superior al bajar ---- */
  const barra = $('header.superior');
  if (barra) {
    const sombra = () => barra.classList.toggle('sombra', scrollY > 4);
    addEventListener('scroll', sombra, { passive: true }); sombra();
  }

  /* ---- Avatares en las listas de miembros ---- */
  $$('.miembros li').forEach(li => {
    const nombre = (li.firstChild?.textContent || '').trim();
    if (!nombre) return;
    const a = document.createElement('span');
    a.className = 'avatar'; a.setAttribute('aria-hidden', 'true');
    a.style.setProperty('--h', matiz(nombre));
    a.textContent = nombre.split(/\s+/).slice(0, 2).map(p => p[0]).join('').toUpperCase();
    li.prepend(a);
  });
  $$('.quien .avatar').forEach(a => a.style.setProperty('--h', matiz($('.quien-txt strong')?.textContent || '')));

  /* ---- Entrada escalonada de indicadores, paneles y tablas ---- */
  $$('.kpi, .chips, .panel, .tabla-wrap, .tarjeta, .vacio, .estado-ok, .acciones').forEach((el, i) => {
    el.style.setProperty('--i', Math.min(i, 8));
    el.classList.add('aparece');
  });

  /* ---- Números que cuentan hasta su valor ---- */
  const formato = dec => new Intl.NumberFormat('es-ES', { minimumFractionDigits: dec, maximumFractionDigits: dec, useGrouping: 'always' });
  $$('[data-contar]').forEach(el => {
    const fin = parseFloat(el.dataset.contar), dec = +el.dataset.dec || 0, suf = el.dataset.sufijo || '';
    if (!isFinite(fin) || reducir) return;
    const f = formato(dec), t0 = performance.now(), dur = 900;
    const paso = t => {
      const k = Math.min(1, (t - t0) / dur), suave = 1 - Math.pow(1 - k, 3);
      el.textContent = f.format(fin * suave) + suf;
      if (k < 1) requestAnimationFrame(paso);
    };
    requestAnimationFrame(paso);
  });

  /* ---- Barras de consumo: crecen al cargar ---- */
  requestAnimationFrame(() => requestAnimationFrame(() => html.classList.add('listo')));

  /* ---- Tablas: ordenar al pulsar la cabecera y filtrar al escribir ---- */
  const valorDe = td => {
    const v = td.dataset.valor ?? td.textContent.trim();
    const n = parseFloat(String(v).replace(',', '.'));
    return td.dataset.valor !== undefined && isFinite(n) ? n : v;
  };
  // La última fila visible no lleva línea debajo (el borde del contenedor ya cierra la tabla).
  const marcarUltima = cuerpo => {
    const visibles = [...cuerpo.rows].filter(r => !r.hidden);
    [...cuerpo.rows].forEach(r => r.classList.remove('ultima'));
    if (visibles.length) visibles[visibles.length - 1].classList.add('ultima');
  };
  $$('table.ordenable').forEach(tabla => {
    const cuerpo = tabla.tBodies[0];
    if (!cuerpo) return;
    $$('th', tabla).forEach((th, col) => {
      th.tabIndex = 0; th.setAttribute('role', 'button'); th.title = 'Ordenar por esta columna';
      const ordenar = () => {
        const asc = th.getAttribute('aria-sort') !== 'ascending';
        $$('th', tabla).forEach(o => o.removeAttribute('aria-sort'));
        th.setAttribute('aria-sort', asc ? 'ascending' : 'descending');
        const filas = [...cuerpo.rows].filter(r => !r.classList.contains('sin-resultados'));
        filas.sort((a, b) => {
          const x = valorDe(a.cells[col]), y = valorDe(b.cells[col]);
          const r = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y), 'es', { numeric: true });
          return asc ? r : -r;
        });
        filas.forEach(f => cuerpo.appendChild(f));
        const vacia = cuerpo.querySelector('.sin-resultados');
        if (vacia) cuerpo.appendChild(vacia);
        marcarUltima(cuerpo);
      };
      th.addEventListener('click', ordenar);
      th.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); ordenar(); } });
    });

    // Filas clicables: pulsar en cualquier parte de la fila abre el enlace del código.
    $$('tbody tr', tabla).forEach(fila => {
      const enlace = $('a.codigo', fila);
      if (!enlace) return;
      fila.classList.add('clicable');
      fila.addEventListener('click', e => { if (!e.target.closest('a, button')) location.href = enlace.href; });
    });

    // Búsqueda (solo si la tabla lo pide con data-filtro).
    if (tabla.dataset.filtro === undefined) return;
    const caja = document.createElement('div');
    caja.className = 'herramientas';
    caja.innerHTML = '<input type="search" placeholder="Filtrar por código, título o responsable (pulsa /)" aria-label="Filtrar la tabla" autocomplete="off"><span class="contador" aria-live="polite"></span>';
    const envoltorio = tabla.closest('.tabla-wrap') || tabla;
    envoltorio.parentNode.insertBefore(caja, envoltorio);
    const entrada = $('input', caja), contador = $('.contador', caja);
    const total = cuerpo.rows.length;
    const vacia = cuerpo.insertRow();
    vacia.className = 'sin-resultados'; vacia.hidden = true;
    vacia.innerHTML = `<td colspan="${$$('th', tabla).length}">Ningún proyecto coincide con lo que has escrito.</td>`;
    const filtrar = () => {
      const q = sinAcentos(entrada.value.trim());
      let visibles = 0;
      [...cuerpo.rows].forEach(f => {
        if (f === vacia) return;
        const ok = !q || sinAcentos(f.textContent).includes(q);
        f.hidden = !ok; if (ok) visibles++;
      });
      vacia.hidden = visibles !== 0;
      marcarUltima(cuerpo);
      contador.textContent = q ? `${visibles} de ${total}` : `${total} ${total === 1 ? 'proyecto' : 'proyectos'}`;
    };
    entrada.addEventListener('input', filtrar); filtrar();
    addEventListener('keydown', e => {
      if (e.key === '/' && !/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName || '')) { e.preventDefault(); entrada.focus(); }
    });
  });

  /* ---- Contraseña: botón mostrar / ocultar ---- */
  $$('input[type="password"]').forEach(campo => {
    const envuelto = document.createElement('span');
    envuelto.className = 'campo-clave';
    campo.replaceWith(envuelto);
    const b = document.createElement('button');
    b.type = 'button'; b.textContent = 'Mostrar'; b.setAttribute('aria-label', 'Mostrar u ocultar la contraseña');
    b.addEventListener('click', () => {
      const ver = campo.type === 'password';
      campo.type = ver ? 'text' : 'password'; b.textContent = ver ? 'Ocultar' : 'Mostrar'; campo.focus();
    });
    envuelto.append(campo, b);
  });

  /* ---- Pistas al escribir (solo orientan: el servidor valida igualmente y el envío nunca se bloquea) ---- */
  $$('input[data-patron], input[data-min]').forEach(campo => {
    let cuenta = null;
    if (campo.dataset.max) {
      cuenta = document.createElement('span'); cuenta.className = 'cuenta';
      campo.closest('label').after(cuenta);
    }
    const revisar = () => {
      const v = campo.value.trim();
      let bien = true;
      if (campo.dataset.patron) bien = new RegExp(campo.dataset.patron).test(v);
      if (campo.dataset.min) bien = v.length >= +campo.dataset.min && v.length <= +campo.dataset.max;
      campo.classList.toggle('ok', v !== '' && bien);
      campo.classList.toggle('mal', v !== '' && !bien);
      if (cuenta) cuenta.textContent = `${[...v].length} / ${campo.dataset.max}`;
    };
    campo.addEventListener('input', revisar); revisar();
  });
})();
