SET SERVEROUTPUT ON;

DECLARE
  -- VARRAY para guardar productos de una factura
  TYPE t_productos IS VARRAY(100) OF NUMBER;    -- Definimos un tipo de arreglo (máximo 100) de números (códigos de producto)
  v_productos t_productos;                      -- Variable que usará ese VARRAY para almacenar los productos de cada factura

  -- RECORD para agrupar datos de un vendedor
  TYPE t_vendedor IS RECORD (                   -- Definimos un tipo de registro que agrupa info de un vendedor
    rut          VENDEDOR.RUTVENDEDOR%TYPE,     -- Rut del vendedor (mismo tipo que en la tabla VENDEDOR)
    nombre       VENDEDOR.NOMBRE%TYPE,          -- Nombre del vendedor
    sueldo_base  VENDEDOR.SUELDO_BASE%TYPE,     -- Sueldo base
    comision     VENDEDOR.COMISION%TYPE,        -- Porcentaje de comisión
    fecha_cont   VENDEDOR.FECHA_CONTRATO%TYPE,  -- Fecha de contrato
    escolaridad  VENDEDOR.ESCOLARIDAD%TYPE      -- Nivel de escolaridad
  );
  r_vend t_vendedor;                            -- Variable del tipo RECORD para cargar datos de cada vendedor

  -- Cursores
  CURSOR c_vendedores IS
    SELECT RUTVENDEDOR, NOMBRE, SUELDO_BASE, COMISION, FECHA_CONTRATO, ESCOLARIDAD
    FROM VENDEDOR;                              -- Cursor que devuelve todos los vendedores con sus datos

  CURSOR c_ventas_vendedor(p_rut VENDEDOR.RUTVENDEDOR%TYPE) IS
    SELECT NUMFACTURA, TOTAL
    FROM FACTURA
    WHERE RUTVENDEDOR = p_rut;                  -- Cursor con parámetro: devuelve las facturas de un vendedor específico

  CURSOR c_detalle_factura(p_numfactura FACTURA.NUMFACTURA%TYPE) IS
    SELECT CODPRODUCTO, TOTALLINEA
    FROM DETALLE_FACTURA
    WHERE NUMFACTURA = p_numfactura;            -- Cursor con parámetro: devuelve el detalle de una factura (productos y montos)

  -- Variables de cálculo
  total_ventas     NUMBER := 0;                 -- Total de ventas acumuladas por vendedor
  monto_comision   NUMBER := 0;                 -- Monto de la comisión calculada
  porc_antiguedad  NUMBER := 0;                 -- Porcentaje por antigüedad
  porc_escolaridad NUMBER := 0;                 -- Porcentaje por escolaridad
  total_bonos      NUMBER := 0;                 -- Bonos sumados (antigüedad + escolaridad)
  total_pagar      NUMBER := 0;                 -- Monto total final a pagar al vendedor

BEGIN
  -- Recorremos todos los vendedores
  FOR v IN c_vendedores LOOP                    -- Bucle que recorre cada fila devuelta por el cursor c_vendedores

    -- llenamos el record
    r_vend.rut := v.rutvendedor;                -- Guardamos rut en el RECORD
    r_vend.nombre := v.nombre;                  -- Guardamos nombre
    r_vend.sueldo_base := v.sueldo_base;        -- Guardamos sueldo base
    r_vend.comision := NVL(v.comision, 0);      -- Guardamos comisión (si es NULL, lo reemplazamos por 0)
    r_vend.fecha_cont := v.fecha_contrato;      -- Guardamos fecha de contrato
    r_vend.escolaridad := v.escolaridad;        -- Guardamos escolaridad

    -- inicializamos valores
    total_ventas := 0;                          -- Reiniciamos el acumulador de ventas
    monto_comision := 0;                        -- Reiniciamos comisión
    total_bonos := 0;                           -- Reiniciamos bonos
    total_pagar := 0;                           -- Reiniciamos total a pagar

    -- calcular antigüedad
    DECLARE anos NUMBER := 0;                   -- Variable local para almacenar la antigüedad en años
    BEGIN
      IF r_vend.fecha_cont IS NOT NULL THEN     -- Si la fecha de contrato no es nula...
        SELECT TRUNC(MONTHS_BETWEEN(SYSDATE, r_vend.fecha_cont) / 12)
        INTO anos FROM DUAL;                    -- Calculamos la diferencia en años entre hoy y la fecha de contrato
      END IF;

      BEGIN
        SELECT PORCENTAJE
        INTO porc_antiguedad
        FROM TRAMO_ANTIGUEDAD
        WHERE anos BETWEEN ANNOS_CONT_INF AND ANNOS_CONT_SUP; -- Buscamos el porcentaje correspondiente en la tabla de tramos
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          porc_antiguedad := 0;                 -- Si no existe tramo para esa antigüedad, dejamos 0
      END;
    END;

    -- calcular escolaridad
    BEGIN
      SELECT PORC_ASIG_ESCOLARIDAD
      INTO porc_escolaridad
      FROM TRAMO_ESCOLARIDAD
      WHERE ID_ESCOLARIDAD = r_vend.escolaridad; -- Buscamos porcentaje asociado al nivel de escolaridad
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        porc_escolaridad := 0;                  -- Si no existe registro, dejamos 0
    END;

    -- recorrer facturas
    FOR f IN c_ventas_vendedor(r_vend.rut) LOOP -- Recorremos cada factura del vendedor
      v_productos := t_productos();             -- Inicializamos el VARRAY vacío para guardar productos de esta factura

      -- recorrer detalle de factura
      FOR d IN c_detalle_factura(f.numfactura) LOOP -- Recorremos los productos de la factura
        total_ventas := total_ventas + NVL(d.totallinea, 0); -- Sumamos cada línea de la factura al total de ventas
        v_productos.EXTEND;                    -- Aumentamos el tamaño del VARRAY
        v_productos(v_productos.LAST) := d.codproducto; -- Guardamos el código del producto en la última posición
      END LOOP;

      DBMS_OUTPUT.PUT_LINE('Factura '||f.numfactura||' - Productos: '|| v_productos.COUNT);
      -- Mostramos número de factura y cuántos productos tenía
    END LOOP;

    -- cálculos finales
    monto_comision := total_ventas * r_vend.comision; -- Calculamos la comisión según el total vendido
    total_bonos := ROUND(r_vend.sueldo_base * ((porc_antiguedad + porc_escolaridad) / 100), 2); 
    -- Calculamos bonos como % del sueldo base (antigüedad + escolaridad), redondeado a 2 decimales
    total_pagar := r_vend.sueldo_base + monto_comision + total_bonos; -- Sumamos todo para obtener el pago final

    -- mostrar resumen
    DBMS_OUTPUT.PUT_LINE(
      'Vendedor: ' || r_vend.nombre ||                       -- Nombre
      ' | Ventas: ' || TO_CHAR(total_ventas, '999G999G999') || -- Total de ventas con formato
      ' | Comisión: ' || TO_CHAR(monto_comision, '999G999G999') || -- Comisión calculada
      ' | Bonos: ' || TO_CHAR(total_bonos, '999G999G999') ||     -- Bonos
      ' | Total a pagar: ' || TO_CHAR(total_pagar, '999G999G999') -- Pago final
    );
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------------'); -- Separador visual
  END LOOP;

-- manejo de excepciones
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error inesperado: ' || SQLERRM); -- Captura cualquier error y lo muestra
END;
/
